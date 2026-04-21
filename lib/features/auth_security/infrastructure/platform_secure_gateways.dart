import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';

abstract interface class ScreenshotProtectionGateway {
  Future<void> enableSensitiveWindowProtection();

  Future<void> updateRecentTaskProtection({required bool obscured});
}

abstract interface class SecureKeyGateway {
  Future<void> ensureRootKey();

  Future<String> getDatabasePasswordMaterial();
}

abstract interface class BiometricGateway {
  Future<BiometricAvailability> getAvailability();

  Future<bool> authenticate();
}

class DeviceScreenshotProtectionGateway implements ScreenshotProtectionGateway {
  DeviceScreenshotProtectionGateway({required NativeSecurityBridge bridge})
      : _bridge = bridge;

  final NativeSecurityBridge _bridge;

  @override
  Future<void> enableSensitiveWindowProtection() {
    return _bridge.enableScreenshotProtection();
  }

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) {
    return _bridge.updateRecentTaskProtection(obscured: obscured);
  }
}

class DeviceSecureKeyGateway implements SecureKeyGateway {
  DeviceSecureKeyGateway({required NativeSecurityBridge bridge}) : _bridge = bridge;

  final NativeSecurityBridge _bridge;

  @override
  Future<void> ensureRootKey() {
    return _bridge.ensureRootKey();
  }

  @override
  Future<String> getDatabasePasswordMaterial() {
    return _bridge.getDatabasePasswordMaterial();
  }
}

class DeviceBiometricGateway implements BiometricGateway {
  DeviceBiometricGateway({required NativeSecurityBridge bridge}) : _bridge = bridge;

  final NativeSecurityBridge _bridge;

  @override
  Future<bool> authenticate() {
    return _bridge.authenticateWithBiometrics();
  }

  @override
  Future<BiometricAvailability> getAvailability() {
    return _bridge.getBiometricAvailability();
  }
}
