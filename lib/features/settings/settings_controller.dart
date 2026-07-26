import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/alarm.dart';
import '../../data/models/app_settings.dart';
import '../../data/repositories/settings_repository.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

class SettingsController extends AsyncNotifier<AppSettings> {
  late final SettingsRepository _repository;

  @override
  Future<AppSettings> build() async {
    _repository = SettingsRepository();
    return _repository.loadSettings();
  }

  Future<void> setReps(AlarmDifficulty difficulty, int reps) async {
    if (reps < 1) return;
    final current = await future;
    final updated = switch (difficulty) {
      AlarmDifficulty.easy => current.copyWith(easyReps: reps),
      AlarmDifficulty.medium => current.copyWith(mediumReps: reps),
      AlarmDifficulty.hard => current.copyWith(hardReps: reps),
    };
    state = AsyncData(updated);
    await _repository.saveSettings(updated);
  }
}
