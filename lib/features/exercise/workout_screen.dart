import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app/theme/morning_theme.dart';
import '../../core/config.dart';
import '../../core/haptics/haptics_service.dart';
import '../../data/models/alarm.dart';
import '../../data/models/exercise_type.dart';
import '../alarm/alarm_list_controller.dart';
import '../alarm/alarm_service.dart';
import '../alarm/native_alarm_ring_bridge.dart';
import '../alarm/workout_planner.dart';
import '../home/home_screen.dart';
import '../settings/settings_controller.dart';
import 'camera_permission_service.dart';
import 'framing_check.dart';
import 'ghost_silhouette_painter.dart';
import 'pose_painter.dart';
import 'workout_session_controller.dart';
import 'workout_session_repository.dart';

const _tag = '[WorkoutScreen]';

/// The full morning flow: framing check -> countdown -> calibration ->
/// exercise(s) -> completion, drawn from the alarm's stored difficulty and
/// exercise pool at fire time. Reachable from AlarmRingScreen's
/// "Egzersize Başla" button; also works with no matching alarm (falls back
/// to Easy + all four exercises), which is what makes the 10-second test
/// alarm exercise this whole flow end-to-end.
class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key, this.alarmId});

  final String? alarmId;

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen>
    with WidgetsBindingObserver {
  WorkoutSessionController? _controller;
  final _ringBridge = NativeAlarmRingBridge();
  final _permissionService = CameraPermissionService();
  Timer? _permissionPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // AlarmRingScreen already requested this before handing off here, but
    // its own dispose() resets it — re-request so the exercise flow stays
    // at max brightness regardless of that ordering.
    ScreenBrightness().setApplicationScreenBrightness(1.0);
    _initWorkout();
    _permissionPollTimer = Timer.periodic(
      const Duration(milliseconds: AppConfig.cameraPermissionPollIntervalMs),
      (_) => _pollCameraPermission(),
    );
  }

  /// Camera permission is checked once at [WorkoutSessionController.start],
  /// but the user can revoke it from system Settings at any moment during
  /// the exercise. Sound stays untouched either way — it's owned entirely
  /// by AlarmRingService now — this only needs to move the UI to the
  /// existing permission-missing fallback instead of freezing silently or
  /// crashing on a camera error.
  Future<void> _pollCameraPermission() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.state == WorkoutFlowState.checkingPermission ||
        controller.state == WorkoutFlowState.permissionMissing ||
        controller.state == WorkoutFlowState.completed) {
      return;
    }
    final status = await _permissionService.check();
    if (status != CameraPermissionState.granted) {
      debugPrint('$_tag camera permission revoked mid-workout: $status');
      controller.pipeline.pauseCamera();
      setState(() => controller.state = WorkoutFlowState.permissionMissing);
    }
  }

  Future<void> _initWorkout() async {
    final AlarmDifficulty difficulty;
    final Set<ExerciseType> pool;

    // A dev-picked test-alarm config (see home_screen.dart's long-press
    // sheet) takes priority and never corresponds to a real alarm, so it's
    // checked before the alarm-list lookup below.
    final testConfig = AlarmSchedulingService.parseTestAlarmConfig(widget.alarmId);
    if (testConfig != null) {
      difficulty = testConfig.difficulty;
      pool = testConfig.exercisePool;
      debugPrint(
        '$_tag using dev-picked test config: ${difficulty.name}, '
        'pool=${pool.map((type) => type.label).join(", ")}',
      );
    } else {
      final alarms = await ref.read(alarmListControllerProvider.future);
      Alarm? alarm;
      for (final candidate in alarms) {
        if (candidate.id == widget.alarmId) {
          alarm = candidate;
          break;
        }
      }
      difficulty = alarm?.difficulty ?? AlarmDifficulty.easy;
      pool = alarm?.exercisePool ?? ExerciseType.values.toSet();
      if (alarm == null) {
        debugPrint(
          '$_tag no alarm found for id=${widget.alarmId}; falling back to '
          'Easy + all four exercises',
        );
      }
    }

    final settings = await ref.read(settingsControllerProvider.future);
    final workout = drawWorkout(
      difficulty: difficulty,
      pool: pool,
      settings: settings,
    );
    debugPrint(
      '$_tag drew workout: '
      '${workout.exercises.map((e) => e.label).join(', ')} '
      'x${workout.repsPerExercise}',
    );

    final controller = WorkoutSessionController(
      workout: workout,
      alarmId: widget.alarmId ?? 'no_alarm_id',
    );
    controller.addListener(_onControllerChanged);
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    await controller.start();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;
    if (controller.state == WorkoutFlowState.checkingPermission ||
        controller.state == WorkoutFlowState.permissionMissing) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.pipeline.pauseCamera();
    } else if (state == AppLifecycleState.resumed) {
      controller.pipeline.resumeCamera();
    }
  }

  /// The one path completion, emergency exit, and the permission-missing
  /// fallback all converge on. Stopping the ring here — rather than
  /// anywhere ringing starts — is deliberate: AlarmRingService keeps
  /// ringing (lowered, not silenced) through backgrounding, permission
  /// loss, anything short of this.
  Future<void> _exitToHome() async {
    await _ringBridge.stopRinging();
    await WorkoutSessionRepository().clear();
    final alarmId = widget.alarmId;
    if (alarmId != null) {
      await ref
          .read(alarmListControllerProvider.notifier)
          .disableIfOneTime(alarmId);
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionPollTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    ScreenBrightness().resetApplicationScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Theme(
      data: morningTheme,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: controller == null
                ? const Center(child: CircularProgressIndicator())
                : _WorkoutBody(controller: controller, onExit: _exitToHome),
          ),
        ),
      ),
    );
  }
}

class _WorkoutBody extends StatelessWidget {
  const _WorkoutBody({required this.controller, required this.onExit});

  final WorkoutSessionController controller;
  final Future<void> Function() onExit;

  @override
  Widget build(BuildContext context) {
    switch (controller.state) {
      case WorkoutFlowState.checkingPermission:
        return const Center(child: CircularProgressIndicator());
      case WorkoutFlowState.permissionMissing:
        return _PermissionMissingView(controller: controller, onExit: onExit);
      case WorkoutFlowState.framingCheck:
      case WorkoutFlowState.countdown:
      case WorkoutFlowState.calibrating:
      case WorkoutFlowState.exercising:
        return _CameraFlowView(controller: controller, onExit: onExit);
      case WorkoutFlowState.transitioning:
        return _TransitionView(controller: controller, onExit: onExit);
      case WorkoutFlowState.completed:
        return _CompletionView(onExit: onExit);
    }
  }
}

class _PermissionMissingView extends StatelessWidget {
  const _PermissionMissingView({required this.controller, required this.onExit});

  final WorkoutSessionController controller;
  final Future<void> Function() onExit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Kamera izni eksik, egzersiz gösterilemiyor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 8),
            const Text(
              'Alarmı yine de kapatabilirsin.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onExit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: const Text('Alarmı Kapat'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: controller.requestPermissionAndContinue,
              child: const Text('İzin Ver ve Devam Et'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraFlowView extends StatelessWidget {
  const _CameraFlowView({required this.controller, required this.onExit});

  final WorkoutSessionController controller;
  final Future<void> Function() onExit;

  @override
  Widget build(BuildContext context) {
    final pipeline = controller.pipeline;
    final cameraController = pipeline.cameraController;
    final errorMessage = pipeline.errorMessage;

    Widget body;
    if (errorMessage != null) {
      body = Center(
        child: Text(
          'Kamera başlatılamadı: $errorMessage',
          textAlign: TextAlign.center,
        ),
      );
    } else if (cameraController == null || !cameraController.value.isInitialized) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scaleX: -1,
            child: CameraPreview(
              cameraController,
              child: controller.state == WorkoutFlowState.exercising
                  ? CustomPaint(
                      painter: PosePainter(
                        poses: pipeline.poses,
                        imageSize: pipeline.lastImageSize,
                        rotation: pipeline.lastRotation,
                        cameraLensDirection:
                            cameraController.description.lensDirection,
                      ),
                    )
                  : null,
            ),
          ),
          _buildOverlay(context),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        // Always shown here: this view only renders for framingCheck/
        // countdown/calibrating/exercising in the first place.
        Positioned(
          top: 16,
          right: 16,
          child: _EmergencyExitButton(onConfirmed: onExit),
        ),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    switch (controller.state) {
      case WorkoutFlowState.framingCheck:
        return _FramingOverlay(message: controller.pipeline.framing.message);
      case WorkoutFlowState.countdown:
        return _FramingOverlay(
          message: controller.pipeline.framing.message,
          countdownValue: controller.countdownValue,
        );
      case WorkoutFlowState.calibrating:
        return _CalibratingOverlay(controller: controller);
      case WorkoutFlowState.exercising:
        return _ExercisingOverlay(controller: controller);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _FramingOverlay extends StatelessWidget {
  const _FramingOverlay({required this.message, this.countdownValue});

  final String message;
  final int? countdownValue;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: CustomPaint(
            painter: const GhostSilhouettePainter(),
            size: MediaQuery.sizeOf(context),
          ),
        ),
        if (countdownValue != null)
          Center(
            child: Text(
              '$countdownValue',
              style: const TextStyle(
                fontSize: 160,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: Center(
            child: Text(
              message,
              style: const TextStyle(fontSize: 22),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

class _CalibratingOverlay extends StatelessWidget {
  const _CalibratingOverlay({required this.controller});

  final WorkoutSessionController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sabit dur...', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: controller.counting.calibrationProgress),
          ],
        ),
      ),
    );
  }
}

class _ExercisingOverlay extends StatelessWidget {
  const _ExercisingOverlay({required this.controller});

  final WorkoutSessionController controller;

  @override
  Widget build(BuildContext context) {
    final counting = controller.counting;
    final target = counting.targetReps;
    final progress = target == 0 ? 0.0 : counting.totalReps / target;
    final framingReady =
        controller.pipeline.framing.status == FramingStatus.ready;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            controller.currentExercise.label,
            style: const TextStyle(fontSize: 20),
          ),
          Text(
            '${counting.totalReps}',
            style: const TextStyle(
              fontSize: 180,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
              height: 1,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 240,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
            ),
          ),
          if (!framingReady) ...[
            const SizedBox(height: 16),
            Text(
              controller.pipeline.framing.message,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransitionView extends StatefulWidget {
  const _TransitionView({required this.controller, required this.onExit});

  final WorkoutSessionController controller;
  final Future<void> Function() onExit;

  @override
  State<_TransitionView> createState() => _TransitionViewState();
}

class _TransitionViewState extends State<_TransitionView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
      Duration(seconds: AppConfig.exerciseTransitionSeconds),
      widget.controller.continueToNextExercise,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nextExercise =
        widget.controller.workout.exercises[widget.controller.currentExerciseIndex + 1];
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sırada', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              Text(
                nextExercise.label,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  _timer?.cancel();
                  widget.controller.continueToNextExercise();
                },
                child: const Text('Devam Et'),
              ),
            ],
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: _EmergencyExitButton(onConfirmed: widget.onExit),
        ),
      ],
    );
  }
}

class _CompletionView extends StatefulWidget {
  const _CompletionView({required this.onExit});

  final Future<void> Function() onExit;

  @override
  State<_CompletionView> createState() => _CompletionViewState();
}

class _CompletionViewState extends State<_CompletionView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    HapticsService().completionPulse();
    _exitTimer = Timer(const Duration(seconds: 3), widget.onExit);
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(
      fit: StackFit.expand,
      children: [
        const Center(
          child: Text(
            'Günaydın',
            style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
          ),
        ),
        AnimatedBuilder(
          animation: _flashController,
          builder: (context, child) {
            final t = _flashController.value;
            // One quick fade in, then out.
            final opacity = t < 0.5 ? t * 2 : (1 - t) * 2;
            return IgnorePointer(
              child: Container(color: accent.withValues(alpha: opacity * 0.6)),
            );
          },
        ),
      ],
    );
  }
}

class _EmergencyExitButton extends StatefulWidget {
  const _EmergencyExitButton({required this.onConfirmed});

  final Future<void> Function() onConfirmed;

  @override
  State<_EmergencyExitButton> createState() => _EmergencyExitButtonState();
}

class _EmergencyExitButtonState extends State<_EmergencyExitButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: AppConfig.emergencyExitHoldSeconds),
  );

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener(_onStatusChanged);
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _holdController.reset();
      _showConfirmDialog();
    }
  }

  Future<void> _showConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acil Çıkış'),
        content: const Text(
          'Egzersizi durdurup alarmı kapatmak istiyor musun?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onConfirmed();
    }
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _holdController.forward(),
      onLongPressEnd: (_) => _holdController.reverse(),
      onLongPressCancel: () => _holdController.reverse(),
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (context, child) {
          return Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black45,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: _holdController.value,
                    strokeWidth: 3,
                    color: Colors.redAccent,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const Icon(Icons.close, color: Colors.white, size: 18),
              ],
            ),
          );
        },
      ),
    );
  }
}
