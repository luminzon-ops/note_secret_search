part of 'security_orchestrator_test.dart';

void _registerSecurityUnlockOrderCases() {
  test(
    'biometric unlock removes the shield before marking session unlocked',
    () async {
      final sessionController = LockSessionController();
      final screenshotGateway = _RecordingScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          expect(obscured, isFalse);
          expect(sessionController.state.isUnlocked, isFalse);
        },
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: screenshotGateway,
      );

      final unlocked = await orchestrator.unlockWithBiometrics();

      expect(unlocked, isTrue);
      expect(screenshotGateway.obscuredUpdates, [false]);
      expect(sessionController.state.isUnlocked, isTrue);
    },
  );

  test('biometric unlock installs typed system session keys', () async {
    final sessionKeyStore = DatabaseSessionKeyStore();
    final sessionController = LockSessionController(
      onLock: sessionKeyStore.clear,
    );
    final unlockMaterial = NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List.fromList(List<int>.filled(32, 5)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 6)),
      unlockMethod: 'system',
    );
    final secureKeyGateway = _RecordingSecureKeyGateway(
      systemUnlockResult: unlockMaterial,
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: _RecordingScreenshotProtectionGateway(),
      biometricGateway: _UnexpectedBiometricAuthenticationGateway(),
      secureKeyGateway: secureKeyGateway,
      sessionKeyStore: sessionKeyStore,
    );

    expect(await orchestrator.unlockWithBiometrics(), isTrue);

    expect(secureKeyGateway.systemUnlockCalls, 1);
    expect(
      sessionKeyStore.requireCurrent().withFieldKey(
        (key) => Uint8List.fromList(key),
      ),
      everyElement(6),
    );
    expect(unlockMaterial.isCleared, isTrue);
  });

  test(
    'pin recovery rebinds system authentication before opening data',
    () async {
      final sessionController = LockSessionController();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        securityState: _nativeSecurityState(
          pinConfigured: true,
          systemRebindRequired: true,
        ),
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        secureKeyGateway: secureKeyGateway,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
      );

      final unlocked = await orchestrator.unlockWithPin(
        pin: '2468',
        expectedLockEpoch: 0,
      );

      expect(unlocked, isTrue);
      expect(secureKeyGateway.rebindCalls, 1);
      expect(secureKeyGateway.lastPin, '2468');
    },
  );

  test('cancelled system rebind does not revoke a valid pin unlock', () async {
    final sessionController = LockSessionController();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      securityState: _nativeSecurityState(
        pinConfigured: true,
        systemRebindRequired: true,
      ),
      rebindError: const NativeSecurityException(
        code: 'AUTH_CANCELLED',
        message: null,
        details: null,
      ),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      secureKeyGateway: secureKeyGateway,
      screenshotGateway: _RecordingScreenshotProtectionGateway(),
    );

    final unlocked = await orchestrator.unlockWithPin(
      pin: '2468',
      expectedLockEpoch: 0,
    );

    expect(unlocked, isTrue);
    expect(secureKeyGateway.rebindCalls, 1);
  });

  test(
    'system provisioning opens the database and unlocks the session',
    () async {
      final sessionController = LockSessionController();
      final provisionMaterial = NativeUnlockResult(
        keyId: '123e4567-e89b-42d3-a456-426614174000',
        databaseKey: Uint8List.fromList(List<int>.filled(32, 0x31)),
        fieldKey: Uint8List.fromList(List<int>.filled(32, 0x42)),
        unlockMethod: 'system',
      );
      final secureKeyGateway = _RecordingSecureKeyGateway(
        provisionResult: provisionMaterial,
      );
      final database = _RecordingAppDatabase();
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: secureKeyGateway,
        database: database,
      );

      expect(await orchestrator.provisionWithSystemAuth(), isTrue);

      expect(secureKeyGateway.provisionCalls, 1);
      expect(secureKeyGateway.systemUnlockCalls, 0);
      expect(database.state.status, DatabaseLifecycleStatus.open);
      expect(sessionController.isUnlocked, isTrue);
      expect(provisionMaterial.isCleared, isTrue);
    },
  );

  test('unlock waits for the database before removing the shield', () async {
    final sessionController = LockSessionController();
    final openStarted = Completer<void>();
    final releaseOpen = Completer<void>();
    final database = _RecordingAppDatabase(
      onOpen: (_) async {
        openStarted.complete();
        await releaseOpen.future;
      },
    );
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      database: database,
    );

    final unlocking = orchestrator.unlockWithBiometrics();
    await openStarted.future;

    expect(database.state.status, DatabaseLifecycleStatus.opening);
    expect(sessionController.isUnlocked, isFalse);
    expect(screenshotGateway.obscuredUpdates, isEmpty);

    releaseOpen.complete();
    expect(await unlocking, isTrue);
    expect(database.state.status, DatabaseLifecycleStatus.open);
    expect(screenshotGateway.obscuredUpdates, [false]);
    expect(sessionController.isUnlocked, isTrue);
  });
}
