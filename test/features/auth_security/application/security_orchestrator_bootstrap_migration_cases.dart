part of 'security_orchestrator_test.dart';

void _registerSecurityBootstrapMigrationCases() {
  test(
    'initialize loads security state without provisioning a root key',
    () async {
      final sessionController = LockSessionController();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        securityState: _nativeSecurityState(pinConfigured: true),
      );
      final database = _RecordingAppDatabase();
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: secureKeyGateway,
        database: database,
      );

      await orchestrator.initialize();

      expect(secureKeyGateway.securityStateCalls, 1);
      expect(secureKeyGateway.provisionCalls, 0);
      expect(database.state.status, DatabaseLifecycleStatus.locked);
      expect(sessionController.isUnlocked, isFalse);
      expect(sessionController.state.pinEnabled, isTrue);
    },
  );

  test(
    'initialize leaves legacy migration pending without authenticating',
    () async {
      final sessionController = LockSessionController();
      final migration = _RecordingLegacySecurityMigration();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        securityState: const NativeSecurityState(
          status: NativeSecurityStatus.legacyMigrationRequired,
          keyId: null,
          pinConfigured: false,
          deviceCredentialAvailable: true,
          strongBiometricAvailable: true,
          securityLevel: KeySecurityLevel.unknown,
        ),
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: secureKeyGateway,
        legacySecurityMigration: migration,
      );

      await orchestrator.initialize();

      expect(migration.calls, 0);
      expect(secureKeyGateway.securityStateCalls, 1);
      expect(sessionController.state.pinEnabled, isFalse);
      expect(sessionController.isUnlocked, isFalse);
    },
  );

  test('explicit legacy migration refreshes state and stays locked', () async {
    final sessionController = LockSessionController();
    final migration = _RecordingLegacySecurityMigration();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      securityStates: <NativeSecurityState>[
        const NativeSecurityState(
          status: NativeSecurityStatus.legacyMigrationRequired,
          keyId: null,
          pinConfigured: false,
          deviceCredentialAvailable: true,
          strongBiometricAvailable: true,
          securityLevel: KeySecurityLevel.unknown,
        ),
        _nativeSecurityState(pinConfigured: true),
      ],
    );
    final database = _RecordingAppDatabase();
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: _RecordingScreenshotProtectionGateway(),
      secureKeyGateway: secureKeyGateway,
      database: database,
      legacySecurityMigration: migration,
    );

    await orchestrator.initialize();
    final refreshed = await orchestrator.migrateLegacySecurity();

    expect(refreshed.status, NativeSecurityStatus.locked);
    expect(migration.calls, 1);
    expect(secureKeyGateway.securityStateCalls, 2);
    expect(sessionController.state.pinEnabled, isTrue);
    expect(sessionController.isUnlocked, isFalse);
    expect(database.state.status, DatabaseLifecycleStatus.locked);
  });
}
