import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../data/models/exercise_type.dart';
import '../alarm/workout_planner.dart';
import 'camera_permission_service.dart';
import 'exercise_counting_controller.dart';
import 'framing_check.dart';
import 'pose_pipeline.dart';

const _tag = '[WorkoutSession]';

enum WorkoutFlowState {
  checkingPermission,
  permissionMissing,
  framingCheck,
  countdown,
  calibrating,
  exercising,
  transitioning,
  completed,
}

/// Owns the whole "alarm rang, now do the workout" flow: one shared camera
/// + pose session across every exercise (never torn down between them),
/// the framing-check -> countdown -> calibration hand-off, and advancing
/// through the drawn workout's exercise list. UI (WorkoutScreen) only reads
/// [state] and calls the handful of user-triggered methods below — all the
/// sequencing logic lives here, per CLAUDE.md's "dedicated controller,
/// never inline in widgets" rule.
class WorkoutSessionController extends ChangeNotifier {
  WorkoutSessionController({
    required this.workout,
    PosePipelineController? pipeline,
    ExerciseCountingController? counting,
    CameraPermissionService? permissionService,
  }) : pipeline = pipeline ?? PosePipelineController(),
       counting = counting ?? ExerciseCountingController(),
       _permissionService = permissionService ?? CameraPermissionService() {
    this.pipeline.addListener(_onPoseFrame);
    this.counting.addListener(_onCountingChanged);
  }

  final Workout workout;
  final PosePipelineController pipeline;
  final ExerciseCountingController counting;
  final CameraPermissionService _permissionService;

  WorkoutFlowState state = WorkoutFlowState.checkingPermission;
  int currentExerciseIndex = 0;
  int countdownValue = AppConfig.countdownSeconds;
  Timer? _countdownTimer;

  ExerciseType get currentExercise => workout.exercises[currentExerciseIndex];
  bool get isLastExercise =>
      currentExerciseIndex == workout.exercises.length - 1;

  Future<void> start() async {
    final permissionState = await _permissionService.check();
    if (permissionState != CameraPermissionState.granted) {
      // Verified at alarm-creation time specifically to prevent this — if
      // it's still missing here, something unusual happened (permission
      // revoked after scheduling). Log loudly, but never trap the user.
      debugPrint(
        '$_tag !!! CAMERA PERMISSION MISSING AT ALARM FIRE TIME !!! '
        'state=$permissionState',
      );
      state = WorkoutFlowState.permissionMissing;
      notifyListeners();
      return;
    }
    await _proceedAfterPermission();
  }

  Future<void> requestPermissionAndContinue() async {
    final permissionState = await _permissionService.request();
    if (permissionState != CameraPermissionState.granted) {
      debugPrint('$_tag permission still not granted after request: $permissionState');
      notifyListeners();
      return;
    }
    await _proceedAfterPermission();
  }

  Future<void> _proceedAfterPermission() async {
    state = WorkoutFlowState.framingCheck;
    counting.selectExercise(currentExercise);
    counting.setTargetReps(workout.repsPerExercise);
    notifyListeners();
    await pipeline.initialize();
  }

  void continueToNextExercise() {
    if (isLastExercise) return;
    currentExerciseIndex++;
    counting.setTargetReps(workout.repsPerExercise);
    counting.startExerciseWithExistingCalibration(currentExercise);
    state = WorkoutFlowState.exercising;
    debugPrint('$_tag continueToNextExercise: ${currentExercise.label}');
    notifyListeners();
  }

  void _onPoseFrame() {
    final framingReady = pipeline.framing.status == FramingStatus.ready;

    switch (state) {
      case WorkoutFlowState.framingCheck:
        if (framingReady) _startCountdown();
        notifyListeners();
      case WorkoutFlowState.countdown:
        if (!framingReady) _cancelCountdown();
        notifyListeners();
      case WorkoutFlowState.calibrating:
      case WorkoutFlowState.exercising:
        counting.onPoseUpdate(
          poses: pipeline.poses,
          framing: pipeline.framing,
          frameHeight: pipeline.lastImageSize.height,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );
      // counting's own notifyListeners() reaches us via _onCountingChanged.
      case WorkoutFlowState.checkingPermission:
      case WorkoutFlowState.permissionMissing:
      case WorkoutFlowState.transitioning:
      case WorkoutFlowState.completed:
        break;
    }
  }

  void _startCountdown() {
    state = WorkoutFlowState.countdown;
    countdownValue = AppConfig.countdownSeconds;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      countdownValue--;
      if (countdownValue <= 0) {
        timer.cancel();
        _beginCalibrationOrExercise();
      }
      notifyListeners();
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    state = WorkoutFlowState.framingCheck;
  }

  void _beginCalibrationOrExercise() {
    if (counting.calibrationReference == null) {
      counting.startCalibration();
      state = WorkoutFlowState.calibrating;
      debugPrint('$_tag starting calibration for ${currentExercise.label}');
    } else {
      counting.startExerciseWithExistingCalibration(currentExercise);
      state = WorkoutFlowState.exercising;
    }
    notifyListeners();
  }

  void _onCountingChanged() {
    if (state == WorkoutFlowState.calibrating &&
        counting.phase == CountingPhase.counting) {
      state = WorkoutFlowState.exercising;
      debugPrint('$_tag calibration complete, exercising: ${currentExercise.label}');
    }
    if (state == WorkoutFlowState.exercising && counting.completed) {
      _onExerciseCompleted();
    }
    notifyListeners();
  }

  void _onExerciseCompleted() {
    debugPrint(
      '$_tag exercise complete: ${currentExercise.label} '
      '(${currentExerciseIndex + 1}/${workout.exercises.length})',
    );
    state = isLastExercise
        ? WorkoutFlowState.completed
        : WorkoutFlowState.transitioning;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    pipeline.removeListener(_onPoseFrame);
    counting.removeListener(_onCountingChanged);
    pipeline.dispose();
    counting.dispose();
    super.dispose();
  }
}
