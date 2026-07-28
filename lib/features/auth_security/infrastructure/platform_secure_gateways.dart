import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';

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
  DeviceSecureKeyGateway({required NativeSecurityBridge bridge})
    : _bridge = bridge;

  final NativeSecurityBridge _bridge;

  @override
  Future<NativeSecurityState> getSecurityState() {
    return _bridge.getSecurityState();
  }

  @override
  Future<NativeUnlockResult> provisionWithSystemAuth() {
    return _bridge.provisionWithSystemAuth();
  }

  @override
  Future<NativeUnlockResult> unlockWithSystemAuth() {
    return _bridge.unlockWithSystemAuth();
  }

  @override
  Future<void> configurePin({required String pin}) {
    return _bridge.configurePin(pin: pin);
  }

  @override
  Future<NativeUnlockResult> unlockWithPin({required String pin}) {
    return _bridge.unlockWithPin(pin: pin);
  }

  @override
  Future<void> rebindSystemAuthWithPin({required String pin}) {
    return _bridge.rebindSystemAuthWithPin(pin: pin);
  }

  @override
  Future<void> removePin() {
    return _bridge.removePin();
  }
}

class DeviceBiometricGateway implements BiometricGateway {
  DeviceBiometricGateway({required NativeSecurityBridge bridge})
    : _bridge = bridge;

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
