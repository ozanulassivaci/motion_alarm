import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/config.dart';
import '../../core/feedback/feedback_service.dart';
import 'calibration.dart';
import 'exercise_definitions.dart';
import 'exercise_session.dart';
import 'framing_check.dart';

const _tag = '[ExerciseCounting]';

enum CountingPhase { idle, calibrating, counting }

/// Owns calibration -> exercise-session -> feedback, driven by pose frames
/// the dev screen feeds in from PosePipelineController — the "camera ->
/// pose -> rep-count loop lives in a dedicated controller, never inline in
/// widgets" rule from CLAUDE.md, applied to the counting half of that loop.
class ExerciseCountingController extends ChangeNotifier {
  ExerciseCountingController({FeedbackService? feedbackService})
    : _feedback = feedbackService ?? FeedbackService();

  final FeedbackService _feedback;

  ExerciseType? selectedType;
  int targetReps = AppConfig.defaultTargetReps;
  CountingPhase phase = CountingPhase.idle;
  bool completed = false;

  CalibrationCapture? _calibrationCapture;
  CalibrationReference? calibrationReference;
  ExerciseSession? _session;

  // Reps already credited before this ExerciseSession instance existed —
  // set when resuming a persisted mid-exercise session (see
  // startExerciseWithExistingCalibration's resumeReps param), so a resume
  // doesn't need to replay pose history or touch RepCounter/ExerciseSession
  // internals at all.
  int _resumeOffset = 0;

  double get calibrationProgress => _calibrationCapture?.progress ?? 0;
  List<RepChannelSnapshot> get channels => _session?.channels ?? const [];
  int get totalReps => _resumeOffset + (_session?.totalReps ?? 0);

  bool get beepEnabled => _feedback.beepEnabled;
  set beepEnabled(bool value) {
    _feedback.beepEnabled = value;
    notifyListeners();
  }

  void setTargetReps(int value) {
    if (value < 1) return;
    targetReps = value;
    notifyListeners();
  }

  void selectExercise(ExerciseType type) {
    selectedType = type;
    phase = CountingPhase.idle;
    _calibrationCapture = null;
    calibrationReference = null;
    _session = null;
    _resumeOffset = 0;
    completed = false;
    notifyListeners();
  }

  void startCalibration() {
    if (selectedType == null) return;
    _calibrationCapture = CalibrationCapture();
    calibrationReference = null;
    _session = null;
    _resumeOffset = 0;
    completed = false;
    phase = CountingPhase.calibrating;
    debugPrint('$_tag startCalibration: exercise=${selectedType!.label}');
    notifyListeners();
  }

  void reset() {
    phase = CountingPhase.idle;
    _calibrationCapture = null;
    calibrationReference = null;
    _session = null;
    _resumeOffset = 0;
    completed = false;
    notifyListeners();
  }

  /// Starts counting a new exercise reusing an already-established
  /// calibration, skipping the calibration step entirely — for the 2nd/3rd
  /// exercise within one workout, since CLAUDE.md's calibration happens
  /// once per session, not once per exercise. No-ops if nothing has been
  /// calibrated yet (call [startCalibration] first for exercise 1).
  ///
  /// [resumeReps] credits reps already counted before this call, when
  /// resuming a persisted mid-exercise session after the process was
  /// killed — see WorkoutSessionController.
  void startExerciseWithExistingCalibration(
    ExerciseType type, {
    int resumeReps = 0,
  }) {
    final reference = calibrationReference;
    if (reference == null) return;
    selectedType = type;
    completed = false;
    _resumeOffset = resumeReps;
    _session = createExerciseSession(type, reference);
    phase = CountingPhase.counting;
    debugPrint(
      '$_tag startExerciseWithExistingCalibration: ${type.label} '
      'resumeReps=$resumeReps',
    );
    notifyListeners();
  }

  /// Called by the dev screen once per processed pose frame.
  void onPoseUpdate({
    required List<Pose> poses,
    required FramingCheckResult framing,
    required double frameHeight,
    required int timestampMs,
  }) {
    switch (phase) {
      case CountingPhase.idle:
        return;
      case CountingPhase.calibrating:
        _handleCalibrationFrame(poses, framing, frameHeight, timestampMs);
        return;
      case CountingPhase.counting:
        _handleCountingFrame(poses, framing, timestampMs);
        return;
    }
  }

  void _handleCalibrationFrame(
    List<Pose> poses,
    FramingCheckResult framing,
    double frameHeight,
    int timestampMs,
  ) {
    final capture = _calibrationCapture;
    if (capture == null) return;

    if (framing.status == FramingStatus.ready && poses.isNotEmpty) {
      capture.addSample(
        landmarks: poses.first.landmarks,
        frameHeight: frameHeight,
        timestampMs: timestampMs,
      );
    }

    if (capture.isComplete) {
      final reference = capture.build();
      final type = selectedType;
      _calibrationCapture = null;
      if (reference != null && type != null) {
        calibrationReference = reference;
        _session = createExerciseSession(type, reference);
        phase = CountingPhase.counting;
        debugPrint('$_tag calibration complete for ${type.label}');
      } else {
        phase = CountingPhase.idle;
        debugPrint('$_tag calibration FAILED to produce a reference');
      }
    }
    notifyListeners();
  }

  void _handleCountingFrame(
    List<Pose> poses,
    FramingCheckResult framing,
    int timestampMs,
  ) {
    final session = _session;
    if (session == null) return;

    // A completed set is done: stop feeding it frames entirely, rather than
    // letting the session keep counting past the target.
    if (completed) return;

    // Freeze: do not count through bad tracking. The dev screen surfaces
    // `framing` directly, so no separate "why" needs to be stored here.
    if (framing.status != FramingStatus.ready || poses.isEmpty) {
      notifyListeners();
      return;
    }

    final newReps = session.update(poses.first.landmarks, timestampMs);
    if (newReps > 0) {
      final afterReps = totalReps;
      final isFinalStretch =
          afterReps < targetReps &&
          afterReps > targetReps - AppConfig.finalStretchRepCount;
      unawaited(_feedback.onValidRep(isFinalStretch: isFinalStretch));
      debugPrint('$_tag rep confirmed: total=$afterReps/$targetReps');

      if (afterReps >= targetReps && !completed) {
        completed = true;
        unawaited(_feedback.onCompletion());
        debugPrint('$_tag set complete');
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }
}
