import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/models/alarm.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/exercise_type.dart';

const _tag = '[WorkoutPlanner]';

@immutable
class Workout {
  const Workout({required this.exercises, required this.repsPerExercise});

  final List<ExerciseType> exercises;
  final int repsPerExercise;
}

/// Draws the exercises required by [difficulty] randomly from [pool], per
/// CLAUDE.md's difficulty section (easy=1, medium=2 different, hard=3
/// different). If the pool has fewer exercises than the difficulty needs,
/// draws all of the pool's exercises rather than repeating one — logged
/// loudly since it means the alarm won't get the full difficulty's variety.
Workout drawWorkout({
  required AlarmDifficulty difficulty,
  required Set<ExerciseType> pool,
  required AppSettings settings,
  Random? random,
}) {
  final requiredCount = switch (difficulty) {
    AlarmDifficulty.easy => 1,
    AlarmDifficulty.medium => 2,
    AlarmDifficulty.hard => 3,
  };
  final reps = switch (difficulty) {
    AlarmDifficulty.easy => settings.easyReps,
    AlarmDifficulty.medium => settings.mediumReps,
    AlarmDifficulty.hard => settings.hardReps,
  };

  var available = pool.toList();
  if (available.isEmpty) {
    // Shouldn't happen — the create/edit screen validates at least one
    // exercise is selected — but never produce an unusable empty workout
    // at fire time.
    debugPrint('$_tag pool was empty; falling back to all four exercises');
    available = ExerciseType.values.toList();
  }

  available.shuffle(random ?? Random());
  final actualCount = requiredCount < available.length
      ? requiredCount
      : available.length;
  if (actualCount < requiredCount) {
    debugPrint(
      '$_tag pool has only ${available.length} exercise(s) but '
      '${difficulty.name} needs $requiredCount distinct ones; using all '
      '${available.length} instead of repeating one',
    );
  }

  return Workout(
    exercises: available.take(actualCount).toList(),
    repsPerExercise: reps,
  );
}
