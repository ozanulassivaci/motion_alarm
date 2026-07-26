import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'workout_session_state.dart';

class WorkoutSessionLocalStore {
  WorkoutSessionLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _sessionKey = 'workout_session';

  Future<WorkoutSessionState?> read() async {
    final raw = await _preferences.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    return WorkoutSessionState.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> write(WorkoutSessionState session) async {
    await _preferences.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    await _preferences.remove(_sessionKey);
  }
}
