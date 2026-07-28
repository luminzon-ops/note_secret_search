import 'package:note_secret_search/features/auth_security/domain/security_models.dart';

abstract interface class NativeSecurityBridge {
  Future<void> enableScreenshotProtection();

  Future<void> updateRecentTaskProtection({required bool obscured});

  Future<NativeSecurityState> getSecurityState();

  Future<NativeUnlockResult> provisionWithSystemAuth({
    String reason = '启用安全存储',
  });

  Future<NativeUnlockResult> unlockWithSystemAuth({String reason = '解锁保险库'});

  Future<void> configurePin({required String pin, String reason = '配置备用 PIN'});

  Future<NativeUnlockResult> unlockWithPin({required String pin});

  Future<void> rebindSystemAuthWithPin({
    required String pin,
    String reason = '恢复系统认证',
  });

  Future<void> removePin({String reason = '移除备用 PIN'});

  Future<void> lock();

  Future<BiometricAvailability> getBiometricAvailability();

  Future<bool> authenticateWithBiometrics({String reason = '解锁保险库'});
}

abstract interface class NativeSecurityMigrationBridge {
  Future<NativeUnlockResult> beginLegacyMigration({String reason = '升级安全存储'});

  Future<NativeLegacyMigrationState> getLegacyMigrationState();

  Future<NativeLegacyMigrationState> prepareLegacyMigrationBackup(String keyId);

  Future<NativeLegacyMigrationState> prepareLegacyMigrationPending(
    String keyId,
  );

  Future<NativeLegacyMigrationState> markLegacyMigrationRowsCopied(
    String keyId,
  );

  Future<NativeLegacyMigrationState> markLegacyMigrationValidated(String keyId);

  Future<NativeLegacyMigrationState> activateLegacyMigration(String keyId);

  Future<NativeLegacyMigrationState> markLegacyMigrationPostSwapValidated(
    String keyId,
  );

  Future<NativeLegacyMigrationState> cleanupLegacyMigrationFiles(String keyId);

  Future<void> commitLegacyMigration({
    required String keyId,
    required String activeDigest,
  });

  Future<void> finishLegacyMigration(String keyId);

  Future<void> abortLegacyMigration();
}

abstract interface class ScreenshotProtectionGateway {
  Future<void> enableSensitiveWindowProtection();

  Future<void> updateRecentTaskProtection({required bool obscured});
}

abstract interface class SecureKeyGateway {
  Future<NativeSecurityState> getSecurityState();

  Future<NativeUnlockResult> provisionWithSystemAuth();

  Future<NativeUnlockResult> unlockWithSystemAuth();

  Future<void> configurePin({required String pin});

  Future<NativeUnlockResult> unlockWithPin({required String pin});

  Future<void> rebindSystemAuthWithPin({required String pin});

  Future<void> removePin();
}

abstract interface class BiometricGateway {
  Future<BiometricAvailability> getAvailability();

  Future<bool> authenticate();
}
