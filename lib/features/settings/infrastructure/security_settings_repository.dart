import 'package:note_secret_search/features/settings/domain/security_settings.dart';

abstract interface class SecuritySettingsRepository {
  Future<SecuritySettings> load();

  Future<void> save(SecuritySettings settings);

  Future<int> loadAutoLockSeconds();

  Future<void> savePinMaterial(String pin);

  Future<bool> verifyPin(String pin);

  Future<bool> hasPinMaterial();
}
