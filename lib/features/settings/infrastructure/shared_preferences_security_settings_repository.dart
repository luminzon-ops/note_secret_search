import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/domain/security_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesSecuritySettingsRepository
    implements SecuritySettingsRepository {
  SharedPreferencesSecuritySettingsRepository({
    required Future<SharedPreferences> Function() loadPreferences,
  }) : _preferences = loadPreferences();

  final Future<SharedPreferences> _preferences;

  static const _biometricPreferredKey = 'security.biometric_preferred';
  static const _autoLockSecondsKey = 'security.auto_lock_seconds';
  static const _clipboardClearSecondsKey = 'security.clipboard_clear_seconds';

  @override
  Future<SecuritySettings> load() async {
    final preferences = await _preferences;
    return SecuritySettings(
      pinEnabled: false,
      biometricPreferred: preferences.getBool(_biometricPreferredKey) ?? true,
      autoLockSeconds: preferences.getInt(_autoLockSecondsKey) ?? 30,
      clipboardClearSeconds:
          preferences.getInt(_clipboardClearSecondsKey) ?? 60,
    );
  }

  @override
  Future<int> loadAutoLockSeconds() async {
    final preferences = await _preferences;
    return preferences.getInt(_autoLockSecondsKey) ?? 30;
  }

  @override
  Future<void> save(SecuritySettings settings) async {
    final preferences = await _preferences;
    await preferences.setBool(
      _biometricPreferredKey,
      settings.biometricPreferred,
    );
    await preferences.setInt(_autoLockSecondsKey, settings.autoLockSeconds);
    await preferences.setInt(
      _clipboardClearSecondsKey,
      settings.clipboardClearSeconds,
    );
  }
}
