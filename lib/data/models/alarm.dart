import 'package:flutter/foundation.dart';

/// Placeholder for the later exercise-pool phase; does not affect anything
/// in Phase 1 beyond being stored alongside the alarm.
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

  Alarm copyWith({
    int? hour,
    int? minute,
    bool? enabled,
    Set<int>? repeatDays,
    AlarmDifficulty? difficulty,
  }) {
    return Alarm(
      id: id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
      repeatDays: repeatDays ?? this.repeatDays,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'hour': hour,
    'minute': minute,
    'enabled': enabled,
    'repeatDays': repeatDays.toList(),
    'difficulty': difficulty.name,
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
    );
  }
}
