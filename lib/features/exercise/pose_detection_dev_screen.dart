import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_permission_service.dart';
import 'pose_painter.dart';
import 'pose_pipeline.dart';

/// Dev-only screen: opens the camera + pose pipeline directly, without
/// setting an alarm, so the whole pipeline can be iterated on quickly.
class PoseDetectionDevScreen extends StatefulWidget {
  const PoseDetectionDevScreen({super.key});

  @override
  State<PoseDetectionDevScreen> createState() =>
      _PoseDetectionDevScreenState();
}

class _PoseDetectionDevScreenState extends State<PoseDetectionDevScreen>
    with WidgetsBindingObserver {
  final _permissionService = CameraPermissionService();
  final _pipeline = PosePipelineController();

  CameraPermissionState? _permissionState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final state = await _permissionService.check();
    if (!mounted) return;
    setState(() => _permissionState = state);
    if (state == CameraPermissionState.granted) {
      await _pipeline.initialize();
    }
  }

  Future<void> _requestPermission() async {
    final state = await _permissionService.request();
    if (!mounted) return;
    setState(() => _permissionState = state);
    if (state == CameraPermissionState.granted) {
      await _pipeline.initialize();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_permissionState != CameraPermissionState.granted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _pipeline.pauseCamera();
    } else if (state == AppLifecycleState.resumed) {
      _pipeline.resumeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pipeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Kamera + Poz Testi')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_permissionState) {
      case null:
        return const Center(child: CircularProgressIndicator());
      case CameraPermissionState.denied:
        return _PermissionRationale(
          message: 'Egzersizi görebilmek için kamera izni gerekiyor.',
          buttonLabel: 'İzin Ver',
          onPressed: _requestPermission,
        );
      case CameraPermissionState.permanentlyDenied:
        return _PermissionRationale(
          message:
              'Kamera izni reddedildi. Devam etmek için ayarlardan izin '
              'vermen gerekiyor.',
          buttonLabel: 'Ayarları Aç',
          onPressed: _permissionService.openSettings,
        );
      case CameraPermissionState.granted:
        return AnimatedBuilder(
          animation: _pipeline,
          builder: (context, _) => _CameraPoseView(pipeline: _pipeline),
        );
    }
  }
}

class _PermissionRationale extends StatelessWidget {
  const _PermissionRationale({
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String message;
  final String buttonLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

class _CameraPoseView extends StatelessWidget {
  const _CameraPoseView({required this.pipeline});

  final PosePipelineController pipeline;

  @override
  Widget build(BuildContext context) {
    final controller = pipeline.cameraController;
    final errorMessage = pipeline.errorMessage;
    if (errorMessage != null) {
      return Center(
        child: Text(
          'Kamera başlatılamadı: $errorMessage',
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Mirrored so the preview feels like looking in a mirror; the
        // overlay is mirrored identically (it's the CameraPreview's own
        // child, sharing the same bounds) so alignment is unaffected.
        Transform.scale(
          scaleX: -1,
          child: CameraPreview(
            controller,
            child: CustomPaint(
              painter: PosePainter(
                poses: pipeline.poses,
                imageSize: pipeline.lastImageSize,
                rotation: pipeline.lastRotation,
                cameraLensDirection: controller.description.lensDirection,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${pipeline.framing.message} · '
                '${pipeline.fps.toStringAsFixed(0)} fps',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
