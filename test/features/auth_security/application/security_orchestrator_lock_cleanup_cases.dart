part of 'security_orchestrator_test.dart';

void _registerSecurityLockCleanupCases() {
  test(
    'pin unlock installs copied session keys and lock clears them',
    () async {
      final sessionKeyStore = DatabaseSessionKeyStore();
      final sessionController = LockSessionController(
        onLock: sessionKeyStore.clear,
      );
      final unlockMaterial = NativeUnlockResult(
        keyId: '123e4567-e89b-42d3-a456-426614174000',
        databaseKey: Uint8List.fromList(List<int>.filled(32, 7)),
        fieldKey: Uint8List.fromList(List<int>.filled(32, 9)),
        unlockMethod: 'pin',
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: _RecordingSecureKeyGateway(
          unlockResult: unlockMaterial,
        ),
        sessionKeyStore: sessionKeyStore,
      );

      expect(
        await orchestrator.unlockWithPin(
          pin: '2468',
          expectedLockEpoch: sessionController.lockEpoch,
        ),
        isTrue,
      );

      final installed = sessionKeyStore.requireCurrent();
      expect(
        installed.withDatabaseKey((key) => Uint8List.fromList(key)),
        everyElement(7),
      );
      expect(
        installed.withFieldKey((key) => Uint8List.fromList(key)),
        everyElement(9),
      );
      expect(unlockMaterial.isCleared, isTrue);

      sessionController.lock();

      expect(installed.isCleared, isTrue);
      expect(sessionKeyStore.hasKeys, isFalse);
    },
  );

  test('lock revokes database access before clearing session keys', () async {
    final sessionController = LockSessionController();
    final sessionKeyStore = DatabaseSessionKeyStore();
    final closeStarted = Completer<void>();
    final releaseClose = Completer<void>();
    final database = _RecordingAppDatabase(
      onClose: () async {
        expect(sessionController.isUnlocked, isTrue);
        closeStarted.complete();
        await releaseClose.future;
      },
    );
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      sessionKeyStore: sessionKeyStore,
      database: database,
    );
    expect(await orchestrator.unlockWithBiometrics(), isTrue);
    screenshotGateway.obscuredUpdates.clear();

    final locking = orchestrator.lock();
    await closeStarted.future;

    expect(screenshotGateway.obscuredUpdates, [true]);
    expect(database.state.status, DatabaseLifecycleStatus.closing);
    expect(sessionController.isUnlocked, isFalse);
    expect(sessionKeyStore.hasKeys, isTrue);

    releaseClose.complete();
    await locking;

    expect(database.state.status, DatabaseLifecycleStatus.locked);
    expect(sessionKeyStore.hasKeys, isFalse);
  });
}
