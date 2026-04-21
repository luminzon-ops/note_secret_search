import 'package:flutter/services.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';

abstract interface class NativeSecurityBridge {
  Future<void> enableScreenshotProtection();

  Future<void> updateRecentTaskProtection({required bool obscured});

  Future<void> ensureRootKey();

  Future<String> getDatabasePasswordMaterial();

  Future<BiometricAvailability> getBiometricAvailability();

  Future<bool> authenticateWithBiometrics({String reason = '解锁保险库'});
}

class MethodChannelNativeSecurityBridge implements NativeSecurityBridge {
  const MethodChannelNativeSecurityBridge();

  static const MethodChannel _channel = MethodChannel(
    'note_secret_search/native_security',
  );

  @override
  Future<void> enableScreenshotProtection() async {
    await _channel.invokeMethod<void>('enableScreenshotProtection');
  }

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {
    await _channel.invokeMethod<void>(
      'updateRecentTaskProtection',
      <String, Object?>{'obscured': obscured},
    );
  }

  @override
  Future<void> ensureRootKey() async {
    await _channel.invokeMethod<void>('ensureRootKey');
  }

  @override
  Future<String> getDatabasePasswordMaterial() async {
    final value = await _channel.invokeMethod<String>('getDatabasePasswordMaterial');
    return value ?? 'fallback-db-password-material';
  }

  @override
  Future<BiometricAvailability> getBiometricAvailability() async {
    final raw = await _channel.invokeMethod<String>('getBiometricAvailability');
    return switch (raw) {
      'available' => BiometricAvailability.available,
      'not_enrolled' => BiometricAvailability.notEnrolled,
      _ => BiometricAvailability.unavailable,
    };
  }

  @override
  Future<bool> authenticateWithBiometrics({String reason = '解锁保险库'}) async {
    final result = await _channel.invokeMethod<bool>(
      'authenticateWithBiometrics',
      <String, Object?>{'reason': reason},
    );
    return result ?? false;
  }
}
