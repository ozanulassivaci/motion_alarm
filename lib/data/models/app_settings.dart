import 'package:flutter/foundation.dart';

import '../../core/config.dart';

/// User-adjustable rep counts per difficulty, seeded from CLAUDE.md's
/// defaults (AppConfig.defaultEasyReps/defaultMediumReps/defaultHardReps).
@immutable
class AppSettings {
  const AppSettings({
    required this.easyReps,
    required this.mediumReps,
    required this.hardReps,
  });

  factory AppSettings.defaults() => const AppSettings(
    easyReps: AppConfig.defaultEasyReps,
    mediumReps: AppConfig.defaultMediumReps,
    hardReps: AppConfig.defaultHardReps,
  );

  final int easyReps;
  final int mediumReps;
  final int hardReps;

  AppSettings copyWith({int? easyReps, int? mediumReps, int? hardReps}) {
    return AppSettings(
      easyReps: easyReps ?? this.easyReps,
      mediumReps: mediumReps ?? this.mediumReps,
      hardReps: hardReps ?? this.hardReps,
    );
  }

  Map<String, dynamic> toJson() => {
    'easyReps': easyReps,
    'mediumReps': mediumReps,
    'hardReps': hardReps,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      easyReps: json['easyReps'] as int? ?? defaults.easyReps,
      mediumReps: json['mediumReps'] as int? ?? defaults.mediumReps,
      hardReps: json['hardReps'] as int? ?? defaults.hardReps,
    );
  }
}
