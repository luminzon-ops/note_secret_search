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

enum NativeLegacyMigrationStage {
  detected,
  keyringReady,
  backupReady,
  pendingCreated,
  rowsCopied,
  validated,
  oldMoved,
  newActivated,
  postSwapValidated,
  cleanupComplete,
}

class NativeLegacyMigrationState {
  const NativeLegacyMigrationState({
    required this.stage,
    required this.keyId,
    required this.sourcePath,
    required this.pendingPath,
    required this.activePath,
    required this.sourceDigest,
    required this.pendingDigest,
    required this.activeDigest,
  });

  final NativeLegacyMigrationStage stage;
  final String? keyId;
  final String sourcePath;
  final String pendingPath;
  final String activePath;
  final String? sourceDigest;
  final String? pendingDigest;
  final String? activeDigest;
}

class NativeSecurityState {
  const NativeSecurityState({
    required this.status,
    required this.keyId,
    required this.pinConfigured,
    required this.deviceCredentialAvailable,
    required this.strongBiometricAvailable,
    required this.securityLevel,
    this.systemRebindRequired = false,
    this.pinResetRequired = false,
  });

  final NativeSecurityStatus status;
  final String? keyId;
  final bool pinConfigured;
  final bool deviceCredentialAvailable;
  final bool strongBiometricAvailable;
  final KeySecurityLevel securityLevel;
  final bool systemRebindRequired;
  final bool pinResetRequired;
}

class NativeUnlockResult {
  NativeUnlockResult({
    required this.keyId,
    required this.databaseKey,
    required this.fieldKey,
    required this.unlockMethod,
    this.searchIndexFingerprintKey,
    this.legacyDatabasePassword,
  });

  final String keyId;
  final Uint8List databaseKey;
  final Uint8List fieldKey;
  final Uint8List? searchIndexFingerprintKey;
  final String unlockMethod;
  final Uint8List? legacyDatabasePassword;

  bool _isCleared = false;

  bool get isCleared => _isCleared;

  void clear() {
    databaseKey.fillRange(0, databaseKey.length, 0);
    fieldKey.fillRange(0, fieldKey.length, 0);
    searchIndexFingerprintKey?.fillRange(
      0,
      searchIndexFingerprintKey!.length,
      0,
    );
    legacyDatabasePassword?.fillRange(0, legacyDatabasePassword!.length, 0);
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
