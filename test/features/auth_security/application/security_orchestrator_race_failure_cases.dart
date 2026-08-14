part of 'security_orchestrator_test.dart';

void _registerSecurityRaceFailureCases() {
  test('biometric result completes while the app is inactive', () async {
    final sessionController = LockSessionController();
    final unlockMaterial = NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List.fromList(List<int>.filled(32, 3)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 4)),
      unlockMethod: 'system',
    );
    final authenticationBlocker = Completer<NativeUnlockResult>();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      systemUnlockFuture: authenticationBlocker.future,
    );
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    var visibility = AppUnlockVisibility.foreground;
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      secureKeyGateway: secureKeyGateway,
      appUnlockVisibility: () => visibility,
    );

    final unlockFuture = orchestrator.unlockWithBiometrics();
    await _waitUntil(() => secureKeyGateway.systemUnlockCalls == 1);
    visibility = AppUnlockVisibility.inactive;
    authenticationBlocker.complete(unlockMaterial);

    expect(await unlockFuture, isTrue);
    expect(sessionController.isUnlocked, isTrue);
    expect(screenshotGateway.obscuredUpdates, isEmpty);
    expect(unlockMaterial.isCleared, isTrue);
  });

  for (final visibility in <AppUnlockVisibility>[
    AppUnlockVisibility.background,
  ]) {
    test(
      'biometric result is rejected when visibility is $visibility',
      () async {
        final sessionController = LockSessionController();
        final unlockMaterial = NativeUnlockResult(
          keyId: '123e4567-e89b-42d3-a456-426614174000',
          databaseKey: Uint8List.fromList(List<int>.filled(32, 3)),
          fieldKey: Uint8List.fromList(List<int>.filled(32, 4)),
          unlockMethod: 'system',
        );
        final authenticationBlocker = Completer<NativeUnlockResult>();
        final secureKeyGateway = _RecordingSecureKeyGateway(
          systemUnlockFuture: authenticationBlocker.future,
        );
        final sessionKeyStore = DatabaseSessionKeyStore();
        var currentVisibility = AppUnlockVisibility.foreground;
        final database = _RecordingAppDatabase();
        final orchestrator = _buildOrchestrator(
          sessionController: sessionController,
          screenshotGateway: _RecordingScreenshotProtectionGateway(),
          secureKeyGateway: secureKeyGateway,
          sessionKeyStore: sessionKeyStore,
          database: database,
          appUnlockVisibility: () => currentVisibility,
        );

        final unlockFuture = orchestrator.unlockWithBiometrics();
        await _waitUntil(() => secureKeyGateway.systemUnlockCalls == 1);
        currentVisibility = visibility;
        authenticationBlocker.complete(unlockMaterial);

        expect(await unlockFuture, isFalse);
        expect(sessionController.isUnlocked, isFalse);
        expect(sessionKeyStore.hasKeys, isFalse);
        expect(database.state.status, DatabaseLifecycleStatus.locked);
        expect(unlockMaterial.isCleared, isTrue);
      },
    );
  }

  test(
    'a concurrent unlock is rejected before requesting new key material',
    () async {
      final sessionController = LockSessionController();
      final firstMaterial = NativeUnlockResult(
        keyId: '123e4567-e89b-42d3-a456-426614174000',
        databaseKey: Uint8List.fromList(List<int>.filled(32, 0x17)),
        fieldKey: Uint8List.fromList(List<int>.filled(32, 0x29)),
        unlockMethod: 'system',
      );
      final authenticationBlocker = Completer<NativeUnlockResult>();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        systemUnlockFuture: authenticationBlocker.future,
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: secureKeyGateway,
      );

      final firstUnlock = orchestrator.unlockWithBiometrics();
      await _waitUntil(() => secureKeyGateway.systemUnlockCalls == 1);

      final concurrentUnlock = await orchestrator.unlockWithPin(
        pin: '2468',
        expectedLockEpoch: sessionController.lockEpoch,
      );
      authenticationBlocker.complete(firstMaterial);
      final firstResult = await firstUnlock;

      expect(concurrentUnlock, isFalse);
      expect(secureKeyGateway.pinUnlockCalls, 0);
      expect(firstResult, isTrue);
      expect(sessionController.isUnlocked, isTrue);
      expect(firstMaterial.isCleared, isTrue);
    },
  );

  test(
    'database open failure stays sanitized and clears unlock keys',
    () async {
      final sessionController = LockSessionController();
      final sessionKeyStore = DatabaseSessionKeyStore();
      final database = _RecordingAppDatabase(
        onOpen: (_) async {
          throw const DatabaseLifecycleException('database_open_failed');
        },
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        sessionKeyStore: sessionKeyStore,
        database: database,
      );

      await expectLater(
        orchestrator.unlockWithBiometrics(),
        throwsA(
          isA<DatabaseLifecycleException>().having(
            (error) => error.code,
            'code',
            'database_open_failed',
          ),
        ),
      );

      expect(sessionController.isUnlocked, isFalse);
      expect(sessionKeyStore.hasKeys, isFalse);
      expect(database.state.status, DatabaseLifecycleStatus.locked);
    },
  );

  test('biometric unlock stays locked when shield removal fails', () async {
    final sessionController = LockSessionController();
    final screenshotGateway = _RecordingScreenshotProtectionGateway(
      onUpdate: (_) => Future<void>.error(StateError('shield failed')),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
    );

    final unlocked = await orchestrator.unlockWithBiometrics();

    expect(unlocked, isFalse);
    expect(sessionController.state.isUnlocked, isFalse);
  });

  test('biometric result is discarded after a newer lock epoch', () async {
    final sessionController = LockSessionController();
    final unlockMaterial = NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List.fromList(List<int>.filled(32, 3)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 4)),
      unlockMethod: 'system',
    );
    final authenticationBlocker = Completer<NativeUnlockResult>();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      systemUnlockFuture: authenticationBlocker.future,
    );
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      secureKeyGateway: secureKeyGateway,
    );

    final unlockFuture = orchestrator.unlockWithBiometrics();
    await _waitUntil(() => secureKeyGateway.systemUnlockCalls == 1);

    sessionController.lock();
    authenticationBlocker.complete(unlockMaterial);

    expect(await unlockFuture, isFalse);
    expect(screenshotGateway.obscuredUpdates, isEmpty);
    expect(sessionController.state.isUnlocked, isFalse);
    expect(unlockMaterial.isCleared, isTrue);
  });

  test(
    'pin unlock waits for shield removal before marking session unlocked',
    () async {
      final sessionController = LockSessionController();
      final unlockMaterial = _pinUnlockMaterial();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        unlockResult: unlockMaterial,
      );
      final shieldBlocker = Completer<void>();
      final screenshotGateway = _RecordingScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          expect(obscured, isFalse);
          expect(sessionController.state.isUnlocked, isFalse);
          await shieldBlocker.future;
        },
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: screenshotGateway,
        secureKeyGateway: secureKeyGateway,
      );

      unawaited(
        Future<void>(() {
          orchestrator.unlockWithPin(
            pin: '2468',
            expectedLockEpoch: sessionController.state.lockEpoch,
          );
        }),
      );
      await _waitUntil(() => screenshotGateway.obscuredUpdates.isNotEmpty);

      expect(sessionController.state.isUnlocked, isFalse);

      shieldBlocker.complete();
      await _waitUntil(() => sessionController.state.isUnlocked);

      expect(screenshotGateway.obscuredUpdates, [false]);
      expect(secureKeyGateway.lastPin, '2468');
      expect(unlockMaterial.isCleared, isTrue);
    },
  );

  test('pin unlock stays locked when shield removal fails', () async {
    final sessionController = LockSessionController();
    final unlockMaterial = _pinUnlockMaterial();
    final screenshotGateway = _RecordingScreenshotProtectionGateway(
      onUpdate: (_) => Future<void>.error(StateError('shield failed')),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      secureKeyGateway: _RecordingSecureKeyGateway(
        unlockResult: unlockMaterial,
      ),
    );

    unawaited(
      Future<void>(() {
        orchestrator.unlockWithPin(
          pin: '2468',
          expectedLockEpoch: sessionController.state.lockEpoch,
        );
      }),
    );
    await _drainEventQueue();

    expect(screenshotGateway.obscuredUpdates, [false]);
    expect(sessionController.state.isUnlocked, isFalse);
    expect(unlockMaterial.isCleared, isTrue);
  });

  test(
    'pin unlock re-obscures when a newer lock arrives during shield removal',
    () async {
      final sessionController = LockSessionController();
      final shieldBlocker = Completer<void>();
      final screenshotGateway = _RecordingScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          if (!obscured) {
            await shieldBlocker.future;
          }
        },
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: screenshotGateway,
        secureKeyGateway: _RecordingSecureKeyGateway(
          unlockResult: _pinUnlockMaterial(),
        ),
      );
      final expectedLockEpoch = sessionController.state.lockEpoch;

      final unlockFuture = orchestrator.unlockWithPin(
        pin: '2468',
        expectedLockEpoch: expectedLockEpoch,
      );
      await _waitUntil(
        () =>
            screenshotGateway.obscuredUpdates.length == 1 &&
            screenshotGateway.obscuredUpdates.single == false,
      );

      sessionController.lock();
      shieldBlocker.complete();

      expect(await unlockFuture, isFalse);
      expect(screenshotGateway.obscuredUpdates, [false, true]);
      expect(sessionController.state.isUnlocked, isFalse);
    },
  );

  test('native pin failure keeps shield and session locked', () async {
    final sessionController = LockSessionController();
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      unlockError: const NativeSecurityException(
        code: 'PIN_INCORRECT',
        message: null,
        details: null,
      ),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      secureKeyGateway: secureKeyGateway,
    );

    await expectLater(
      orchestrator.unlockWithPin(
        pin: '0000',
        expectedLockEpoch: sessionController.lockEpoch,
      ),
      throwsA(
        isA<NativeSecurityException>().having(
          (error) => error.code,
          'code',
          'PIN_INCORRECT',
        ),
      ),
    );

    expect(secureKeyGateway.lastPin, '0000');
    expect(screenshotGateway.obscuredUpdates, isEmpty);
    expect(sessionController.isUnlocked, isFalse);
  });
}
