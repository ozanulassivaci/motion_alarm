import 'package:flutter/foundation.dart';

import '../../data/models/exercise_type.dart';
import '../alarm/workout_planner.dart';
import 'calibration.dart';

/// Snapshot of an in-progress workout, persisted so it survives the process
/// being killed — per CLAUDE.md, nothing should silently lose progress or
/// dismiss the alarm except completion or a confirmed emergency exit. Only
/// the *already-drawn* [workout] is stored (never re-rolled on resume) and
/// [calibrationReference] (never re-captured on resume).
@immutable
class WorkoutSessionState {
  const WorkoutSessionState({
    required this.alarmId,
    required this.workout,
    required this.currentExerciseIndex,
    required this.repsCompletedForCurrentExercise,
    required this.calibrationReference,
    required this.savedAtEpochMs,
  });

  final String alarmId;
  final Workout workout;
  final int currentExerciseIndex;
  final int repsCompletedForCurrentExercise;
  final CalibrationReference calibrationReference;
  final int savedAtEpochMs;

  WorkoutSessionState copyWith({
    int? currentExerciseIndex,
    int? repsCompletedForCurrentExercise,
    int? savedAtEpochMs,
  }) {
    return WorkoutSessionState(
      alarmId: alarmId,
      workout: workout,
      currentExerciseIndex:
          currentExerciseIndex ?? this.currentExerciseIndex,
      repsCompletedForCurrentExercise:
          repsCompletedForCurrentExercise ?? this.repsCompletedForCurrentExercise,
      calibrationReference: calibrationReference,
      savedAtEpochMs: savedAtEpochMs ?? this.savedAtEpochMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'alarmId': alarmId,
    'workout': {
      'exercises': workout.exercises.map((type) => type.name).toList(),
      'repsPerExercise': workout.repsPerExercise,
    },
    'currentExerciseIndex': currentExerciseIndex,
    'repsCompletedForCurrentExercise': repsCompletedForCurrentExercise,
    'calibrationReference': {
      'torsoLength': calibrationReference.torsoLength,
      'shoulderWidth': calibrationReference.shoulderWidth,
      'legLength': calibrationReference.legLength,
      'standingHipY': calibrationReference.standingHipY,
      'restingKneeY': calibrationReference.restingKneeY,
    },
    'savedAtEpochMs': savedAtEpochMs,
  };

  factory WorkoutSessionState.fromJson(Map<String, dynamic> json) {
    final workoutJson = json['workout'] as Map<String, dynamic>;
    final referenceJson = json['calibrationReference'] as Map<String, dynamic>;
    return WorkoutSessionState(
      alarmId: json['alarmId'] as String,
      workout: Workout(
        exercises: (workoutJson['exercises'] as List<dynamic>)
            .map((name) => ExerciseType.values.byName(name as String))
            .toList(),
        repsPerExercise: workoutJson['repsPerExercise'] as int,
      ),
      currentExerciseIndex: json['currentExerciseIndex'] as int,
      repsCompletedForCurrentExercise:
          json['repsCompletedForCurrentExercise'] as int,
      calibrationReference: CalibrationReference(
        torsoLength: (referenceJson['torsoLength'] as num).toDouble(),
        shoulderWidth: (referenceJson['shoulderWidth'] as num).toDouble(),
        legLength: (referenceJson['legLength'] as num).toDouble(),
        standingHipY: (referenceJson['standingHipY'] as num).toDouble(),
        restingKneeY: (referenceJson['restingKneeY'] as num).toDouble(),
      ),
      savedAtEpochMs: json['savedAtEpochMs'] as int,
    );
  }
}
