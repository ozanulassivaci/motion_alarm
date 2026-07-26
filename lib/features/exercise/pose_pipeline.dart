import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/config.dart';
import 'camera_service.dart';
import 'framing_check.dart';
import 'pose_painter.dart';

const _tag = '[PosePipeline]';

/// Device-orientation-to-degrees map used by the same rotation-compensation
/// formula ML Kit's own Flutter examples use.
const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Owns the camera -> pose -> framing-check loop, per CLAUDE.md's rule that
/// this lives in a dedicated controller, never inline in widgets. Feeds
/// camera frames to ML Kit, dropping (not queuing) frames the detector can't
/// keep up with, and reports the achieved detection FPS.
class PosePipelineController extends ChangeNotifier {
  PosePipelineController({CameraService? cameraService})
    : _cameraService = cameraService ?? CameraService();

  final CameraService _cameraService;
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  bool _isDetecting = false;

  // Monotonic clock for rate-limiting, instead of DateTime.now() — avoids
  // allocating a new DateTime on every single incoming camera frame.
  final _clock = Stopwatch()..start();
  int _lastProcessedAtMs = 0;

  int _frameCountThisSecond = 0;
  Timer? _fpsTimer;

  // Reused across frames instead of writing a downscaled NV21 buffer into a
  // fresh Uint8List every time — see AppConfig.enableManualDownscale.
  Uint8List? _downscaleBuffer;

  // Lets lastImageSize's Size allocation be skipped entirely once the
  // camera's resolution is known (it never changes frame-to-frame).
  int _lastWidth = -1;
  int _lastHeight = -1;

  // Stage 1 profiling (kDebugMode only, zero cost in release): per-stage
  // millisecond timing, accumulated and averaged once per second, to find
  // where per-frame cost actually goes rather than guessing. Stopwatches are
  // long-lived fields (reset + reused), not allocated per frame, so this
  // instrumentation doesn't itself add to the GC pressure it's measuring.
  final _arrivalStopwatch = Stopwatch();
  final _conversionStopwatch = Stopwatch();
  final _inferenceStopwatch = Stopwatch();
  final _postProcessStopwatch = Stopwatch();
  double _arrivalTotalMs = 0;
  int _arrivalCount = 0;
  double _conversionTotalMs = 0;
  int _conversionCount = 0;
  double _inferenceTotalMs = 0;
  int _inferenceCount = 0;
  double _postProcessTotalMs = 0;
  int _postProcessCount = 0;

  CameraController? get cameraController => _cameraService.controller;

  List<Pose> poses = [];
  Size lastImageSize = Size.zero;
  InputImageRotation lastRotation = InputImageRotation.rotation0deg;
  FramingCheckResult framing = const FramingCheckResult(
    status: FramingStatus.noPersonDetected,
    missingLandmarks: [],
  );
  double fps = 0;
  bool isInitializing = false;
  String? errorMessage;

  Future<void> initialize() async {
    isInitializing = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _cameraService.initialize();
      await _cameraService.startImageStream(_onImage);
      _fpsTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        fps = _frameCountThisSecond.toDouble();
        _frameCountThisSecond = 0;
        if (kDebugMode) {
          _logAndResetProfiling();
        } else {
          debugPrint('$_tag detection fps=$fps');
        }
        notifyListeners();
      });
      debugPrint('$_tag initialize: camera + image stream started');
    } catch (error, stackTrace) {
      errorMessage = error.toString();
      debugPrint('$_tag initialize FAILED: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  /// Called on app-lifecycle pause/inactive: releases the camera so it
  /// doesn't leak or crash while backgrounded.
  Future<void> pauseCamera() async {
    _fpsTimer?.cancel();
    _fpsTimer = null;
    await _cameraService.dispose();
    debugPrint('$_tag pauseCamera: camera disposed');
    notifyListeners();
  }

  /// Called on app-lifecycle resume: re-initializes from scratch.
  Future<void> resumeCamera() => initialize();

  void _onImage(CameraImage image) {
    // Camera frame arrival interval: measured for every frame the platform
    // delivers, regardless of whether we go on to drop or process it, since
    // this reflects the raw camera stream rate, not our processing rate.
    if (kDebugMode) {
      if (_arrivalStopwatch.isRunning) {
        _arrivalTotalMs += _arrivalStopwatch.elapsedMicroseconds / 1000;
        _arrivalCount++;
      }
      _arrivalStopwatch
        ..reset()
        ..start();
    }

    if (_isDetecting) return; // drop: previous frame still processing
    final nowMs = _clock.elapsedMilliseconds;
    if (nowMs - _lastProcessedAtMs < AppConfig.poseDetectionMinIntervalMs) {
      return; // drop: rate-capped
    }
    _isDetecting = true;
    _lastProcessedAtMs = nowMs;
    _processImage(image).whenComplete(() => _isDetecting = false);
  }

  Future<void> _processImage(CameraImage image) async {
    final controller = _cameraService.controller;
    if (controller == null) return;

    if (kDebugMode) {
      _conversionStopwatch
        ..reset()
        ..start();
    }
    final inputImage = _inputImageFromCameraImage(image, controller);
    if (kDebugMode) {
      _conversionTotalMs += _conversionStopwatch.elapsedMicroseconds / 1000;
      _conversionCount++;
    }
    if (inputImage == null) return;

    try {
      if (kDebugMode) {
        _inferenceStopwatch
          ..reset()
          ..start();
      }
      final detected = await _poseDetector.processImage(inputImage);
      if (kDebugMode) {
        _inferenceTotalMs += _inferenceStopwatch.elapsedMicroseconds / 1000;
        _inferenceCount++;
        _postProcessStopwatch
          ..reset()
          ..start();
      }

      poses = detected;
      framing = checkFraming(detected);
      _frameCountThisSecond++;
      notifyListeners();

      if (kDebugMode) {
        _postProcessTotalMs +=
            _postProcessStopwatch.elapsedMicroseconds / 1000;
        _postProcessCount++;
      }
    } catch (error) {
      debugPrint('$_tag processImage FAILED: $error');
    }
  }

  void _logAndResetProfiling() {
    double average(double total, int count) => count == 0 ? 0 : total / count;
    debugPrint(
      '$_tag fps=$fps | arrival=${average(_arrivalTotalMs, _arrivalCount).toStringAsFixed(1)}ms '
      'conversion=${average(_conversionTotalMs, _conversionCount).toStringAsFixed(1)}ms '
      'inference=${average(_inferenceTotalMs, _inferenceCount).toStringAsFixed(1)}ms '
      'postProcess=${average(_postProcessTotalMs, _postProcessCount).toStringAsFixed(1)}ms '
      'paint=${PosePainter.averagePaintMs.toStringAsFixed(1)}ms',
    );
    _arrivalTotalMs = 0;
    _arrivalCount = 0;
    _conversionTotalMs = 0;
    _conversionCount = 0;
    _inferenceTotalMs = 0;
    _inferenceCount = 0;
    _postProcessTotalMs = 0;
    _postProcessCount = 0;
    PosePainter.resetPaintStats();
  }

  /// Converts a raw camera frame into the InputImage ML Kit expects,
  /// applying the correct rotation compensation for the front camera's
  /// mirrored sensor mounting. Returns null (frame dropped) for any frame
  /// this can't confidently convert, rather than guessing.
  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraController controller,
  ) {
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      debugPrint(
        '$_tag dropping frame: unexpected format $format '
        '(planes=${image.planes.length})',
      );
      return null;
    }

    if (image.planes.length != 1) {
      debugPrint(
        '$_tag dropping frame: expected 1 plane, got ${image.planes.length}',
      );
      return null;
    }
    final plane = image.planes.first;

    var bytes = plane.bytes;
    var width = image.width;
    var height = image.height;
    var bytesPerRow = plane.bytesPerRow;

    if (AppConfig.enableManualDownscale &&
        format == InputImageFormat.nv21 &&
        width % AppConfig.manualDownscaleFactor == 0 &&
        height % AppConfig.manualDownscaleFactor == 0) {
      bytes = _downscaleNv21(
        bytes,
        width,
        height,
        AppConfig.manualDownscaleFactor,
      );
      width ~/= AppConfig.manualDownscaleFactor;
      height ~/= AppConfig.manualDownscaleFactor;
      bytesPerRow = width; // tightly packed, no row padding
    }

    // Compare raw ints before constructing a Size, so the common case (same
    // camera resolution every frame) allocates nothing at all.
    if (width != _lastWidth || height != _lastHeight) {
      _lastWidth = width;
      _lastHeight = height;
      lastImageSize = Size(width.toDouble(), height.toDouble());
    }
    lastRotation = rotation;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: lastImageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  /// Nearest-neighbor NV21 downscale by an integer factor. Writes into a
  /// buffer allocated once and reused every frame (its size never changes
  /// once the camera resolution is fixed), per the "reuse buffers instead
  /// of allocating each frame" goal.
  Uint8List _downscaleNv21(
    Uint8List src,
    int srcWidth,
    int srcHeight,
    int factor,
  ) {
    final dstWidth = srcWidth ~/ factor;
    final dstHeight = srcHeight ~/ factor;
    final ySize = dstWidth * dstHeight;
    final totalSize = ySize + ySize ~/ 2;

    var dst = _downscaleBuffer;
    if (dst == null || dst.length != totalSize) {
      dst = Uint8List(totalSize);
      _downscaleBuffer = dst;
    }

    // Y plane: sample every `factor`-th row/column.
    for (var y = 0; y < dstHeight; y++) {
      final srcRowStart = (y * factor) * srcWidth;
      final dstRowStart = y * dstWidth;
      for (var x = 0; x < dstWidth; x++) {
        dst[dstRowStart + x] = src[srcRowStart + x * factor];
      }
    }

    // Interleaved VU plane: natively subsampled 2x2 relative to luma, so its
    // own grid is (srcWidth/2 x srcHeight/2) VU pairs; downscale that grid
    // by the same factor to stay consistent with the Y plane above.
    final srcChromaWidth = srcWidth ~/ 2;
    final srcUvStart = srcWidth * srcHeight;
    final dstChromaWidth = dstWidth ~/ 2;
    final dstChromaHeight = dstHeight ~/ 2;
    final dstUvStart = ySize;
    for (var y = 0; y < dstChromaHeight; y++) {
      final srcRowStart = srcUvStart + (y * factor) * srcChromaWidth * 2;
      final dstRowStart = dstUvStart + y * dstChromaWidth * 2;
      for (var x = 0; x < dstChromaWidth; x++) {
        final srcIndex = srcRowStart + (x * factor) * 2;
        final dstIndex = dstRowStart + x * 2;
        dst[dstIndex] = src[srcIndex]; // V
        dst[dstIndex + 1] = src[srcIndex + 1]; // U
      }
    }

    return dst;
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    unawaited(_cameraService.dispose());
    unawaited(_poseDetector.close());
    super.dispose();
  }
}
