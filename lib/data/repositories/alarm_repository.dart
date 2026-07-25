import '../local/alarm_local_store.dart';
import '../models/alarm.dart';

class AlarmRepository {
  AlarmRepository({AlarmLocalStore? store}) : _store = store ?? AlarmLocalStore();

  final AlarmLocalStore _store;

  Future<List<Alarm>> loadAlarms() => _store.readAll();

  Future<void> saveAlarms(List<Alarm> alarms) => _store.writeAll(alarms);

  /// Timestamp-based id: unique enough for a single-user local alarm list,
  /// with no server round-trip to coordinate ids.
  String newAlarmId() => DateTime.now().microsecondsSinceEpoch.toString();
}
