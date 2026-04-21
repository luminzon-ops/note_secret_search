import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/security_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesSecuritySettingsRepository implements SecuritySettingsRepository {
  SharedPreferencesSecuritySettingsRepository({required SharedPreferences preferences})
      : _preferences = preferences;

  final SharedPreferences _preferences;

  static const _pinEnabledKey = 'security.pin_enabled';
  static const _pinMaterialKey = 'security.pin_material';
  static const _biometricPreferredKey = 'security.biometric_preferred';
  static const _autoLockSecondsKey = 'security.auto_lock_seconds';
  static const _clipboardClearSecondsKey = 'security.clipboard_clear_seconds';

  @override
  Future<bool> hasPinMaterial() async {
    return (_preferences.getString(_pinMaterialKey) ?? '').isNotEmpty;
  }

  @override
  Future<SecuritySettings> load() async {
    return SecuritySettings(
      pinEnabled: _preferences.getBool(_pinEnabledKey) ?? false,
      biometricPreferred: _preferences.getBool(_biometricPreferredKey) ?? true,
      autoLockSeconds: _preferences.getInt(_autoLockSecondsKey) ?? 30,
      clipboardClearSeconds: _preferences.getInt(_clipboardClearSecondsKey) ?? 60,
    );
  }

  @override
  Future<int> loadAutoLockSeconds() async {
    return _preferences.getInt(_autoLockSecondsKey) ?? 30;
  }

  @override
  Future<void> save(SecuritySettings settings) async {
    await _preferences.setBool(_pinEnabledKey, settings.pinEnabled);
    await _preferences.setBool(_biometricPreferredKey, settings.biometricPreferred);
    await _preferences.setInt(_autoLockSecondsKey, settings.autoLockSeconds);
    await _preferences.setInt(_clipboardClearSecondsKey, settings.clipboardClearSeconds);
  }

  @override
  Future<void> savePinMaterial(String pin) async {
    await _preferences.setString(_pinMaterialKey, pin);
  }

  @override
  Future<bool> verifyPin(String pin) async {
    return (_preferences.getString(_pinMaterialKey) ?? '') == pin;
  }
}
