import '../local/settings_local_store.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository({SettingsLocalStore? store})
    : _store = store ?? SettingsLocalStore();

  final SettingsLocalStore _store;

  Future<AppSettings> loadSettings() => _store.read();

  Future<void> saveSettings(AppSettings settings) => _store.write(settings);
}
