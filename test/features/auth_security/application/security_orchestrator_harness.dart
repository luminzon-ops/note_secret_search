part of 'security_orchestrator_test.dart';

SecurityOrchestrator _buildOrchestrator({
  required LockSessionController sessionController,
  required ScreenshotProtectionGateway screenshotGateway,
  BiometricGateway? biometricGateway,
  SecureKeyGateway? secureKeyGateway,
  DatabaseSessionKeyStore? sessionKeyStore,
  AppDatabase? database,
  LegacySecurityMigrationRunner? legacySecurityMigration,
  AppUnlockVisibilityReader? appUnlockVisibility,
}) {
  return SecurityOrchestrator(
    biometricGateway: biometricGateway ?? _SuccessfulBiometricGateway(),
    screenshotProtectionGateway: screenshotGateway,
    secureKeyGateway: secureKeyGateway ?? _RecordingSecureKeyGateway(),
    sessionController: sessionController,
    pinStateController: PinStateController(),
    logger: const AppLogger(),
    appUnlockVisibility:
        appUnlockVisibility ?? () => AppUnlockVisibility.foreground,
    sessionKeyStore: sessionKeyStore ?? DatabaseSessionKeyStore(),
    database: database ?? _RecordingAppDatabase(),
    legacySecurityMigration: legacySecurityMigration,
  );
}

NativeUnlockResult _pinUnlockMaterial() {
  return NativeUnlockResult(
    keyId: '123e4567-e89b-42d3-a456-426614174000',
    databaseKey: Uint8List(32),
    fieldKey: Uint8List(32),
    unlockMethod: 'pin',
  );
}

NativeSecurityState _nativeSecurityState({
  required bool pinConfigured,
  bool systemRebindRequired = false,
}) {
  return NativeSecurityState(
    status: NativeSecurityStatus.locked,
    keyId: '123e4567-e89b-42d3-a456-426614174000',
    pinConfigured: pinConfigured,
    deviceCredentialAvailable: true,
    strongBiometricAvailable: true,
    securityLevel: KeySecurityLevel.tee,
    systemRebindRequired: systemRebindRequired,
  );
}

Future<void> _drainEventQueue() async {
  for (var index = 0; index < 10; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100; index += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached before the test timeout.');
}
