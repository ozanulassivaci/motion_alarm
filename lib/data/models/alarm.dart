import 'package:flutter/foundation.dart';

import 'exercise_type.dart';

enum AlarmDifficulty { easy, medium, hard }

@immutable
class Alarm {
  const Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.enabled,
    required this.repeatDays,
    required this.difficulty,
    required this.exercisePool,
  });

  final String id;

  /// 0-23.
  final int hour;

  /// 0-59.
  final int minute;

  final bool enabled;

  /// [DateTime.monday]..[DateTime.sunday]. Empty means a one-time alarm.
  final Set<int> repeatDays;

  final AlarmDifficulty difficulty;

  /// Exercises the user is willing to do; the workout draws randomly from
  /// this pool at fire time. Never empty in practice — the create/edit
  /// screen validates at least one is selected.
  final Set<ExerciseType> exercisePool;

  Alarm copyWith({
    int? hour,
    int? minute,
    bool? enabled,
    Set<int>? repeatDays,
    AlarmDifficulty? difficulty,
    Set<ExerciseType>? exercisePool,
  }) {
    return Alarm(
      id: id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
      repeatDays: repeatDays ?? this.repeatDays,
      difficulty: difficulty ?? this.difficulty,
      exercisePool: exercisePool ?? this.exercisePool,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'hour': hour,
    'minute': minute,
    'enabled': enabled,
    'repeatDays': repeatDays.toList(),
    'difficulty': difficulty.name,
    'exercisePool': exercisePool.map((type) => type.name).toList(),
  };

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'] as String,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      enabled: json['enabled'] as bool,
      repeatDays: (json['repeatDays'] as List<dynamic>)
          .map((day) => day as int)
          .toSet(),
      difficulty: AlarmDifficulty.values.byName(json['difficulty'] as String),
      // Alarms persisted before this field existed default to the full
      // pool, rather than an empty one that could never draw a workout.
      exercisePool: json['exercisePool'] == null
          ? ExerciseType.values.toSet()
          : (json['exercisePool'] as List<dynamic>)
                .map((name) => ExerciseType.values.byName(name as String))
                .toSet(),
    );
  }
}
