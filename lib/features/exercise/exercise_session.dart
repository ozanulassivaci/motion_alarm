import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/config.dart';
import 'calibration.dart';
import 'exercise_definitions.dart';
import 'rep_counter.dart';

/// One rep-counting "channel" worth of debug info for the dev screen's
/// overlay: the raw metric value, current state, running extreme, last
/// confirmed peak/trough, and a human-readable reason nothing was counted.
@immutable
class RepChannelSnapshot {
  const RepChannelSnapshot({
    required this.label,
    required this.metricValue,
    required this.phase,
    required this.extremeValue,
    required this.lastConfirmedPeak,
    required this.lastConfirmedTrough,
    required this.statusMessage,
  });

  factory RepChannelSnapshot.visibilityFrozen(String label) {
    return RepChannelSnapshot(
      label: label,
      metricValue: null,
      phase: null,
      extremeValue: null,
      lastConfirmedPeak: null,
      lastConfirmedTrough: null,
      statusMessage: 'Görünmüyor',
    );
  }

  factory RepChannelSnapshot.fromUpdate(
    String label,
    double metricValue,
    RepCounterUpdate update,
  ) {
    final statusMessage = update.repConfirmed
        ? 'Tekrar sayıldı!'
        : switch (update.rejectionReason) {
            RepRejectionReason.romGate => 'Reddedildi: hareket çok küçük (ROM)',
            RepRejectionReason.durationGate => 'Reddedildi: çok hızlı',
            null => 'İzleniyor',
          };
    return RepChannelSnapshot(
      label: label,
      metricValue: metricValue,
      phase: update.phase,
      extremeValue: update.extremeValue,
      lastConfirmedPeak: update.lastConfirmedPeak,
      lastConfirmedTrough: update.lastConfirmedTrough,
      statusMessage: statusMessage,
    );
  }

  final String label;
  final double? metricValue;
  final RepCounterPhase? phase;
  final double? extremeValue;
  final double? lastConfirmedPeak;
  final double? lastConfirmedTrough;
  final String statusMessage;
}

/// One exercise's live counting session: owns the RepCounter(s) it needs
/// and turns one frame's landmarks into debug info + newly confirmed reps.
abstract class ExerciseSession {
  ExerciseType get type;
  int get totalReps;
  List<RepChannelSnapshot> get channels;

  /// Feeds one frame's landmarks in (only called while framing is ready —
  /// freezing on bad tracking is the caller's job). Returns how many new
  /// reps were confirmed this frame (almost always 0 or 1).
  int update(Map<PoseLandmarkType, PoseLandmark> landmarks, int timestampMs);
}

ExerciseSession createExerciseSession(
  ExerciseType type,
  CalibrationReference calibration,
) {
  return switch (type) {
    ExerciseType.squat => SquatSession(calibration),
    ExerciseType.jumpingJack => JumpingJackSession(calibration),
    ExerciseType.highKnees => HighKneesSession(calibration),
    ExerciseType.overheadReach => OverheadReachSession(calibration),
  };
}

class SquatSession implements ExerciseSession {
  SquatSession(this.calibration)
    : _counter = RepCounter(
        minRepAmplitude: AppConfig.minRepAmplitude,
        romGate: AppConfig.squatRomGate,
        minRepDurationMs: AppConfig.minRepDurationMs,
      );

  final CalibrationReference calibration;
  final RepCounter _counter;
  RepChannelSnapshot? _snapshot;

  @override
  ExerciseType get type => ExerciseType.squat;

  @override
  int get totalReps => _counter.repCount;

  @override
  List<RepChannelSnapshot> get channels => [
    _snapshot ?? RepChannelSnapshot.visibilityFrozen('Squat'),
  ];

  @override
  int update(Map<PoseLandmarkType, PoseLandmark> landmarks, int timestampMs) {
    final metric = squatMetric(landmarks, calibration);
    if (metric == null) {
      _snapshot = RepChannelSnapshot.visibilityFrozen('Squat');
      return 0;
    }
    final result = _counter.update(metric, timestampMs);
    _snapshot = RepChannelSnapshot.fromUpdate('Squat', metric, result);
    return result.repConfirmed ? 1 : 0;
  }
}

class OverheadReachSession implements ExerciseSession {
  OverheadReachSession(this.calibration)
    : _counter = RepCounter(
        minRepAmplitude: AppConfig.minRepAmplitude,
        romGate: AppConfig.overheadReachRomGate,
        minRepDurationMs: AppConfig.minRepDurationMs,
      );

  final CalibrationReference calibration;
  final RepCounter _counter;
  RepChannelSnapshot? _snapshot;

  @override
  ExerciseType get type => ExerciseType.overheadReach;

  @override
  int get totalReps => _counter.repCount;

  @override
  List<RepChannelSnapshot> get channels => [
    _snapshot ?? RepChannelSnapshot.visibilityFrozen('Uzanma'),
  ];

  @override
  int update(Map<PoseLandmarkType, PoseLandmark> landmarks, int timestampMs) {
    final metric = overheadReachMetric(landmarks, calibration);
    if (metric == null) {
      _snapshot = RepChannelSnapshot.visibilityFrozen('Uzanma');
      return 0;
    }
    final result = _counter.update(metric, timestampMs);
    _snapshot = RepChannelSnapshot.fromUpdate('Uzanma', metric, result);
    return result.repConfirmed ? 1 : 0;
  }
}

/// Per-leg state machines, each independently confirming a rep, summed —
/// per CLAUDE.md, "each knee lift above threshold = 1 rep".
class HighKneesSession implements ExerciseSession {
  HighKneesSession(this.calibration)
    : _left = RepCounter(
        minRepAmplitude: AppConfig.minRepAmplitude,
        romGate: AppConfig.highKneeRomGate,
        minRepDurationMs: AppConfig.minRepDurationMs,
      ),
      _right = RepCounter(
        minRepAmplitude: AppConfig.minRepAmplitude,
        romGate: AppConfig.highKneeRomGate,
        minRepDurationMs: AppConfig.minRepDurationMs,
      );

  final CalibrationReference calibration;
  final RepCounter _left;
  final RepCounter _right;
  RepChannelSnapshot? _leftSnapshot;
  RepChannelSnapshot? _rightSnapshot;

  @override
  ExerciseType get type => ExerciseType.highKnees;

  @override
  int get totalReps => _left.repCount + _right.repCount;

  @override
  List<RepChannelSnapshot> get channels => [
    _leftSnapshot ?? RepChannelSnapshot.visibilityFrozen('Sol Diz'),
    _rightSnapshot ?? RepChannelSnapshot.visibilityFrozen('Sağ Diz'),
  ];

  @override
  int update(Map<PoseLandmarkType, PoseLandmark> landmarks, int timestampMs) {
    var newReps = 0;

    final leftMetric = highKneeMetric(
      landmarks[PoseLandmarkType.leftKnee],
      calibration,
    );
    if (leftMetric == null) {
      _leftSnapshot = RepChannelSnapshot.visibilityFrozen('Sol Diz');
    } else {
      final result = _left.update(leftMetric, timestampMs);
      _leftSnapshot = RepChannelSnapshot.fromUpdate(
        'Sol Diz',
        leftMetric,
        result,
      );
      if (result.repConfirmed) newReps++;
    }

    final rightMetric = highKneeMetric(
      landmarks[PoseLandmarkType.rightKnee],
      calibration,
    );
    if (rightMetric == null) {
      _rightSnapshot = RepChannelSnapshot.visibilityFrozen('Sağ Diz');
    } else {
      final result = _right.update(rightMetric, timestampMs);
      _rightSnapshot = RepChannelSnapshot.fromUpdate(
        'Sağ Diz',
        rightMetric,
        result,
      );
      if (result.repConfirmed) newReps++;
    }

    return newReps;
  }
}

/// Ankle-spread and wrist-height are tracked as fully independent
/// extrema-reversal channels; a combined jack only counts once BOTH have
/// independently confirmed their own valid "closed" rep within
/// AppConfig.jumpingJackAlignmentWindowMs of each other — not a same-frame
/// AND, since sparse sampling makes exact-frame coincidence unlikely even
/// for a well-synchronized jack.
class JumpingJackSession implements ExerciseSession {
  JumpingJackSession(this.calibration)
    : _ankle = RepCounter(
        minRepAmplitude: AppConfig.minRepAmplitude,
        romGate: AppConfig.jumpingJackAnkleRomGate,
        minRepDurationMs: AppConfig.minRepDurationMs,
      ),
      _wrist = RepCounter(
        minRepAmplitude: AppConfig.minRepAmplitude,
        romGate: AppConfig.jumpingJackWristRomGate,
        minRepDurationMs: AppConfig.minRepDurationMs,
      );

  final CalibrationReference calibration;
  final RepCounter _ankle;
  final RepCounter _wrist;
  RepChannelSnapshot? _ankleSnapshot;
  RepChannelSnapshot? _wristSnapshot;

  int? _ankleConfirmedAtMs;
  int? _wristConfirmedAtMs;
  int _combinedReps = 0;

  @override
  ExerciseType get type => ExerciseType.jumpingJack;

  @override
  int get totalReps => _combinedReps;

  @override
  List<RepChannelSnapshot> get channels => [
    _ankleSnapshot ?? RepChannelSnapshot.visibilityFrozen('Ayak Açıklığı'),
    _wristSnapshot ?? RepChannelSnapshot.visibilityFrozen('Bilek Yüksekliği'),
  ];

  @override
  int update(Map<PoseLandmarkType, PoseLandmark> landmarks, int timestampMs) {
    final ankleMetric = jumpingJackAnkleMetric(landmarks, calibration);
    if (ankleMetric == null) {
      _ankleSnapshot = RepChannelSnapshot.visibilityFrozen('Ayak Açıklığı');
    } else {
      final result = _ankle.update(ankleMetric, timestampMs);
      _ankleSnapshot = RepChannelSnapshot.fromUpdate(
        'Ayak Açıklığı',
        ankleMetric,
        result,
      );
      if (result.repConfirmed) _ankleConfirmedAtMs = timestampMs;
    }

    final wristMetric = jumpingJackWristMetric(landmarks, calibration);
    if (wristMetric == null) {
      _wristSnapshot = RepChannelSnapshot.visibilityFrozen('Bilek Yüksekliği');
    } else {
      final result = _wrist.update(wristMetric, timestampMs);
      _wristSnapshot = RepChannelSnapshot.fromUpdate(
        'Bilek Yüksekliği',
        wristMetric,
        result,
      );
      if (result.repConfirmed) _wristConfirmedAtMs = timestampMs;
    }

    final ankleAt = _ankleConfirmedAtMs;
    final wristAt = _wristConfirmedAtMs;
    if (ankleAt != null &&
        wristAt != null &&
        (ankleAt - wristAt).abs() <= AppConfig.jumpingJackAlignmentWindowMs) {
      _combinedReps++;
      _ankleConfirmedAtMs = null;
      _wristConfirmedAtMs = null;
      return 1;
    }

    return 0;
  }
}
