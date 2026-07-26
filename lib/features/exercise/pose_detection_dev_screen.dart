import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_permission_service.dart';
import 'exercise_counting_controller.dart';
import 'exercise_definitions.dart';
import 'exercise_session.dart';
import 'pose_painter.dart';
import 'pose_pipeline.dart';

/// Dev-only screen: opens the camera + pose pipeline directly, without
/// setting an alarm, so the whole pipeline — including rep counting — can
/// be iterated on quickly, and tuned against the tester's own body via the
/// debug overlay.
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
  final _counting = ExerciseCountingController();

  CameraPermissionState? _permissionState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pipeline.addListener(_onPoseFrame);
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

  void _onPoseFrame() {
    _counting.onPoseUpdate(
      poses: _pipeline.poses,
      framing: _pipeline.framing,
      frameHeight: _pipeline.lastImageSize.height,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
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
    _pipeline.removeListener(_onPoseFrame);
    _pipeline.dispose();
    _counting.dispose();
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
          animation: Listenable.merge([_pipeline, _counting]),
          builder: (context, _) =>
              _CameraPoseView(pipeline: _pipeline, counting: _counting),
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
  const _CameraPoseView({required this.pipeline, required this.counting});

  final PosePipelineController pipeline;
  final ExerciseCountingController counting;

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
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(child: _ControlPanel(counting: counting)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: _DebugPanel(pipeline: pipeline, counting: counting),
          ),
        ),
      ],
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.counting});

  final ExerciseCountingController counting;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: ExerciseType.values.map((type) {
              final selected = counting.selectedType == type;
              return ChoiceChip(
                label: Text(type.label),
                selected: selected,
                onSelected: counting.phase == CountingPhase.idle
                    ? (_) => counting.selectExercise(type)
                    : null,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          _buildActionRow(context),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context) {
    switch (counting.phase) {
      case CountingPhase.idle:
        return Row(
          children: [
            FilledButton(
              onPressed: counting.selectedType == null
                  ? null
                  : counting.startCalibration,
              child: const Text('Kalibre Et'),
            ),
            const SizedBox(width: 16),
            _TargetRepsStepper(counting: counting),
            const Spacer(),
            _BeepToggle(counting: counting),
          ],
        );
      case CountingPhase.calibrating:
        return Row(
          children: [
            const Text(
              'Sabit dur...',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LinearProgressIndicator(value: counting.calibrationProgress),
            ),
          ],
        );
      case CountingPhase.counting:
        return Row(
          children: [
            Text(
              '${counting.totalReps} / ${counting.targetReps}'
              '${counting.completed ? ' ✓' : ''}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: counting.reset,
              child: const Text('Sıfırla'),
            ),
            const Spacer(),
            _BeepToggle(counting: counting),
          ],
        );
    }
  }
}

class _TargetRepsStepper extends StatelessWidget {
  const _TargetRepsStepper({required this.counting});

  final ExerciseCountingController counting;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Hedef:', style: TextStyle(color: Colors.white)),
        IconButton(
          icon: const Icon(Icons.remove, color: Colors.white),
          onPressed: () => counting.setTargetReps(counting.targetReps - 1),
        ),
        Text(
          '${counting.targetReps}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        IconButton(
          icon: const Icon(Icons.add, color: Colors.white),
          onPressed: () => counting.setTargetReps(counting.targetReps + 1),
        ),
      ],
    );
  }
}

class _BeepToggle extends StatelessWidget {
  const _BeepToggle({required this.counting});

  final ExerciseCountingController counting;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.volume_up, color: Colors.white, size: 18),
        Switch(
          value: counting.beepEnabled,
          onChanged: (value) => counting.beepEnabled = value,
        ),
      ],
    );
  }
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({required this.pipeline, required this.counting});

  final PosePipelineController pipeline;
  final ExerciseCountingController counting;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pipeline.framing.message} · '
            '${pipeline.fps.toStringAsFixed(0)} fps',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (counting.phase == CountingPhase.counting) ...[
            const Divider(color: Colors.white24, height: 12),
            ...counting.channels.map(_buildChannelRow),
          ],
        ],
      ),
    );
  }

  Widget _buildChannelRow(RepChannelSnapshot channel) {
    final metric = channel.metricValue;
    final extreme = channel.extremeValue;
    final peak = channel.lastConfirmedPeak;
    final trough = channel.lastConfirmedTrough;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${channel.label}: '
        '${metric == null ? '—' : metric.toStringAsFixed(2)} '
        '(${channel.phase?.name ?? '—'}, '
        'ext=${extreme == null ? '—' : extreme.toStringAsFixed(2)}, '
        'peak=${peak == null ? '—' : peak.toStringAsFixed(2)}, '
        'trough=${trough == null ? '—' : trough.toStringAsFixed(2)}) '
        '— ${channel.statusMessage}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
