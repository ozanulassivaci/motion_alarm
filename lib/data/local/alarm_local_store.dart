import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm.dart';

class AlarmLocalStore {
  AlarmLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _alarmsKey = 'alarms';

  Future<List<Alarm>> readAll() async {
    final raw = await _preferences.getString(_alarmsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => Alarm.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<void> writeAll(List<Alarm> alarms) async {
    final encoded = jsonEncode(alarms.map((alarm) => alarm.toJson()).toList());
    await _preferences.setString(_alarmsKey, encoded);
  }
}
