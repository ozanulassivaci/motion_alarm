import 'dart:io';

import 'package:camera/camera.dart';

import '../../core/config.dart';

/// Owns the camera lifecycle: picking the front camera, initializing and
/// disposing the controller, and the image stream. Knows nothing about pose
/// detection — see pose_pipeline.dart for that.
class CameraService {
  CameraController? _controller;

  CameraController? get controller => _controller;

  Future<CameraController> initialize() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      frontCamera,
      AppConfig.cameraResolutionPreset,
      enableAudio: false,
      // Caps native capture (and the plugin's own per-frame YUV->NV21
      // conversion) at the source; see the constant's doc comment.
      fps: AppConfig.cameraCaptureFps,
      // A single-plane format is required for the InputImage conversion
      // below to work: nv21 on Android, bgra8888 on iOS.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    _controller = controller;
    return controller;
  }

  Future<void> startImageStream(void Function(CameraImage image) onImage) {
    return _controller?.startImageStream(onImage) ?? Future.value();
  }

  Future<void> stopImageStream() async {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }
}
