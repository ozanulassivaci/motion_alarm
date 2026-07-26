import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsLocalStore {
  SettingsLocalStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _settingsKey = 'app_settings';

  Future<AppSettings> read() async {
    final raw = await _preferences.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return AppSettings.defaults();
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> write(AppSettings settings) async {
    await _preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}
