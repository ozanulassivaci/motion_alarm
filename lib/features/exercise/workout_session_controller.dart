import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config.dart';
import '../../data/models/exercise_type.dart';
import '../alarm/workout_planner.dart';
import 'camera_permission_service.dart';
import 'exercise_counting_controller.dart';
import 'framing_check.dart';
import 'pose_pipeline.dart';
import 'workout_session_repository.dart';
import 'workout_session_state.dart';

const _tag = '[WorkoutSession]';

enum WorkoutFlowState {
  checkingPermission,
  permissionMissing,
  framingCheck,
  countdown,
  calibrating,
  // Full-screen announcement (name + demo animation) shown before every
  // exercise, including the first — reached right after calibration
  // completes, and again after each exercise finishes. No pose frames are
  // forwarded to ExerciseCountingController while this is showing (see
  // _onPoseFrame), even though counting.phase is already "counting" by this
  // point, so reps can never silently accumulate before the user has even
  // seen which exercise is starting.
  intro,
  exercising,
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
    required this.alarmId,
    PosePipelineController? pipeline,
    ExerciseCountingController? counting,
    CameraPermissionService? permissionService,
    WorkoutSessionRepository? sessionRepository,
  }) : pipeline = pipeline ?? PosePipelineController(),
       counting = counting ?? ExerciseCountingController(),
       _permissionService = permissionService ?? CameraPermissionService(),
       _sessionRepository = sessionRepository ?? WorkoutSessionRepository() {
    this.pipeline.addListener(_onPoseFrame);
    this.counting.addListener(_onCountingChanged);
  }

  final Workout workout;

  /// Persistence key for resuming this workout after the process is killed
  /// mid-exercise — see WorkoutSessionRepository. Not necessarily a real
  /// Alarm.id (the dev test-alarm sheet's synthetic payload, or "no alarm
  /// found", both still get a stable-enough key for one run).
  final String alarmId;

  final PosePipelineController pipeline;
  final ExerciseCountingController counting;
  final CameraPermissionService _permissionService;
  final WorkoutSessionRepository _sessionRepository;

  WorkoutFlowState state = WorkoutFlowState.checkingPermission;
  int currentExerciseIndex = 0;
  int countdownValue = AppConfig.countdownSeconds;
  Timer? _countdownTimer;
  int? _lastPersistedTotalReps;

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

    final resumable = await _sessionRepository.loadResumable(alarmId);
    if (resumable != null) {
      await _resumeFrom(resumable);
      return;
    }
    await _proceedAfterPermission();
  }

  /// Restores exactly where a persisted, non-stale session for this
  /// [alarmId] left off — skipping framing-check/countdown/calibration
  /// entirely, since the workout was already drawn and calibration already
  /// captured. Only the current exercise's own rep count needs replaying,
  /// which [ExerciseCountingController.startExerciseWithExistingCalibration]
  /// handles via `resumeReps` without touching pose/RepCounter internals.
  Future<void> _resumeFrom(WorkoutSessionState saved) async {
    currentExerciseIndex = saved.currentExerciseIndex;
    counting.selectExercise(currentExercise);
    counting.calibrationReference = saved.calibrationReference;
    counting.setTargetReps(workout.repsPerExercise);
    counting.startExerciseWithExistingCalibration(
      currentExercise,
      resumeReps: saved.repsCompletedForCurrentExercise,
    );
    _lastPersistedTotalReps = saved.repsCompletedForCurrentExercise;
    state = WorkoutFlowState.exercising;
    notifyListeners();
    await pipeline.initialize();
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

  /// Advances out of the intro screen into actual rep counting — called by
  /// both the intro's auto-advance timer and its manual continue button.
  /// The exercise itself (index, calibration reuse, target reps) is already
  /// fully set up by the time intro is entered (see _onExerciseCompleted /
  /// the calibration-complete branch in _onCountingChanged), so this only
  /// needs to flip the state.
  void confirmIntroAndBeginExercise() {
    if (state != WorkoutFlowState.intro) return;
    state = WorkoutFlowState.exercising;
    notifyListeners();
  }

  Future<void> _persistSession() async {
    final reference = counting.calibrationReference;
    if (reference == null) return;
    await _sessionRepository.save(
      WorkoutSessionState(
        alarmId: alarmId,
        workout: workout,
        currentExerciseIndex: currentExerciseIndex,
        repsCompletedForCurrentExercise: counting.totalReps,
        calibrationReference: reference,
        savedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
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
      case WorkoutFlowState.intro:
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
      state = WorkoutFlowState.intro;
      counting.startExerciseWithExistingCalibration(currentExercise);
    }
    notifyListeners();
  }

  void _onCountingChanged() {
    if (state == WorkoutFlowState.calibrating &&
        counting.phase == CountingPhase.counting) {
      state = WorkoutFlowState.intro;
      debugPrint('$_tag calibration complete, showing intro: ${currentExercise.label}');
    }
    if (state == WorkoutFlowState.exercising && counting.completed) {
      _onExerciseCompleted();
    }
    // Persist only when the rep count actually changes (or on the
    // calibration-complete transition above, where it's still 0) rather
    // than on every processed pose frame — a rep-counted event is the only
    // moment worth a disk write.
    if (state == WorkoutFlowState.exercising &&
        counting.totalReps != _lastPersistedTotalReps) {
      _lastPersistedTotalReps = counting.totalReps;
      unawaited(_persistSession());
    }
    notifyListeners();
  }

  void _onExerciseCompleted() {
    debugPrint(
      '$_tag exercise complete: ${currentExercise.label} '
      '(${currentExerciseIndex + 1}/${workout.exercises.length})',
    );
    if (isLastExercise) {
      state = WorkoutFlowState.completed;
      return;
    }
    currentExerciseIndex++;
    // Set before starting the next exercise's counting below: that call
    // synchronously re-triggers _onCountingChanged (counting's own
    // notifyListeners), and this must already read as "intro", not the
    // just-finished exercise's stale "exercising", when that happens.
    state = WorkoutFlowState.intro;
    counting.setTargetReps(workout.repsPerExercise);
    counting.startExerciseWithExistingCalibration(currentExercise);
    _lastPersistedTotalReps = 0;
    unawaited(_persistSession());
    debugPrint('$_tag next exercise ready, showing intro: ${currentExercise.label}');
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
