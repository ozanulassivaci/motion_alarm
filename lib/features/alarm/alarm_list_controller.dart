import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/alarm.dart';
import '../../data/repositories/alarm_repository.dart';
import 'alarm_service.dart';

/// Overridden in main.dart with the instance that was already `init()`-ed
/// before `runApp`. There is no usable default: scheduling needs the
/// timezone database loaded first.
final alarmSchedulingServiceProvider = Provider<AlarmSchedulingService>((ref) {
  throw UnimplementedError(
    'alarmSchedulingServiceProvider must be overridden in main.dart after '
    'AlarmSchedulingService.init() has completed.',
  );
});

final alarmListControllerProvider =
    AsyncNotifierProvider<AlarmListController, List<Alarm>>(
      AlarmListController.new,
    );

class AlarmListController extends AsyncNotifier<List<Alarm>> {
  late final AlarmRepository _repository;

  @override
  Future<List<Alarm>> build() async {
    _repository = AlarmRepository();
    return _repository.loadAlarms();
  }

  Future<void> addAlarm({
    required int hour,
    required int minute,
    required Set<int> repeatDays,
    required AlarmDifficulty difficulty,
  }) async {
    final current = await future;
    final alarm = Alarm(
      id: _repository.newAlarmId(),
      hour: hour,
      minute: minute,
      enabled: true,
      repeatDays: repeatDays,
      difficulty: difficulty,
    );
    await _persist([...current, alarm]);
    await _schedulingService.scheduleAlarm(alarm);
  }

  Future<void> updateAlarm(Alarm updated) async {
    final current = await future;
    await _persist([
      for (final alarm in current)
        if (alarm.id == updated.id) updated else alarm,
    ]);
    await _schedulingService.scheduleAlarm(updated);
  }

  Future<void> deleteAlarm(String id) async {
    final current = await future;
    await _persist(current.where((alarm) => alarm.id != id).toList());
    await _schedulingService.cancelAlarm(id);
  }

  Future<void> toggleEnabled(String id, bool enabled) async {
    final current = await future;
    Alarm? toggled;
    final next = [
      for (final alarm in current)
        if (alarm.id == id)
          (toggled = alarm.copyWith(enabled: enabled))
        else
          alarm,
    ];
    await _persist(next);
    final toggledAlarm = toggled;
    if (toggledAlarm != null) {
      if (enabled) {
        await _schedulingService.scheduleAlarm(toggledAlarm);
      } else {
        await _schedulingService.cancelAlarm(id);
      }
    }
  }

  /// Called when a fired one-time alarm is dismissed, so the list doesn't
  /// keep showing it as "on" when it will never fire again on its own.
  Future<void> disableIfOneTime(String id) async {
    final current = await future;
    Alarm? alarm;
    for (final candidate in current) {
      if (candidate.id == id) {
        alarm = candidate;
        break;
      }
    }
    if (alarm == null || alarm.repeatDays.isNotEmpty || !alarm.enabled) {
      return;
    }
    await toggleEnabled(id, false);
  }

  AlarmSchedulingService get _schedulingService =>
      ref.read(alarmSchedulingServiceProvider);

  Future<void> _persist(List<Alarm> alarms) async {
    state = AsyncData(alarms);
    await _repository.saveAlarms(alarms);
  }
}
