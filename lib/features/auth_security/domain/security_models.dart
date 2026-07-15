import 'dart:typed_data';

enum PrivacyMode { strict, balanced, custom }

enum AutoLockDuration { immediate, seconds30, minute1, minutes5 }

enum BiometricAvailability { available, unavailable, notEnrolled }

enum NativeSecurityStatus {
  unprovisioned,
  legacyMigrationRequired,
  locked,
  recoveryRequired,
}

enum KeySecurityLevel { strongBox, tee, software, unknown }

class NativeSecurityState {
  const NativeSecurityState({
    required this.status,
    required this.keyId,
    required this.pinConfigured,
    required this.deviceCredentialAvailable,
    required this.strongBiometricAvailable,
    required this.securityLevel,
  });

  final NativeSecurityStatus status;
  final String? keyId;
  final bool pinConfigured;
  final bool deviceCredentialAvailable;
  final bool strongBiometricAvailable;
  final KeySecurityLevel securityLevel;
}

class NativeUnlockResult {
  NativeUnlockResult({
    required this.keyId,
    required this.databaseKey,
    required this.fieldKey,
    required this.unlockMethod,
  });

  final String keyId;
  final Uint8List databaseKey;
  final Uint8List fieldKey;
  final String unlockMethod;

  bool _isCleared = false;

  bool get isCleared => _isCleared;

  void clear() {
    databaseKey.fillRange(0, databaseKey.length, 0);
    fieldKey.fillRange(0, fieldKey.length, 0);
    _isCleared = true;
  }
}

class NativeSecurityException implements Exception {
  const NativeSecurityException({
    required this.code,
    required this.message,
    required this.details,
  });

  final String code;
  final String? message;
  final Object? details;

  @override
  String toString() {
    final description = message;
    if (description == null || description.isEmpty) {
      return 'NativeSecurityException($code)';
    }
    return 'NativeSecurityException($code): $description';
  }
}

class PinPolicy {
  const PinPolicy({
    required this.enabled,
    required this.maxFailures,
    required this.coolDownSeconds,
  });

  final bool enabled;
  final int maxFailures;
  final int coolDownSeconds;
}
