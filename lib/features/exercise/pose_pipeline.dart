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
  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _frameCountThisSecond = 0;
  Timer? _fpsTimer;

  // Stage 1 profiling (kDebugMode only, zero cost in release): per-stage
  // millisecond timing, accumulated and averaged once per second, to find
  // where per-frame cost actually goes rather than guessing.
  final _arrivalStopwatch = Stopwatch();
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

    final now = DateTime.now();
    if (_isDetecting) return; // drop: previous frame still processing
    if (now.difference(_lastProcessedAt).inMilliseconds <
        AppConfig.poseDetectionMinIntervalMs) {
      return; // drop: rate-capped
    }
    _isDetecting = true;
    _lastProcessedAt = now;
    _processImage(image).whenComplete(() => _isDetecting = false);
  }

  Future<void> _processImage(CameraImage image) async {
    final controller = _cameraService.controller;
    if (controller == null) return;

    final conversionStopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    final inputImage = _inputImageFromCameraImage(image, controller);
    if (conversionStopwatch != null) {
      _conversionTotalMs += conversionStopwatch.elapsedMicroseconds / 1000;
      _conversionCount++;
    }
    if (inputImage == null) return;

    try {
      final inferenceStopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      final detected = await _poseDetector.processImage(inputImage);
      if (inferenceStopwatch != null) {
        _inferenceTotalMs += inferenceStopwatch.elapsedMicroseconds / 1000;
        _inferenceCount++;
      }

      final postStopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      poses = detected;
      framing = checkFraming(detected);
      _frameCountThisSecond++;
      notifyListeners();
      if (postStopwatch != null) {
        _postProcessTotalMs += postStopwatch.elapsedMicroseconds / 1000;
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

    lastImageSize = Size(image.width.toDouble(), image.height.toDouble());
    lastRotation = rotation;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: lastImageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    unawaited(_cameraService.dispose());
    unawaited(_poseDetector.close());
    super.dispose();
  }
}
