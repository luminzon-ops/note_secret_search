part of 'app_lock_gate_test.dart';

void _registerAppLockProvisionMigrationCases() {
  testWidgets('first install lock screen does not expose pin setup', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith(
            (ref) => SecurityOrchestrator(
              biometricGateway: _FakeBiometricGateway(),
              screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
              secureKeyGateway: _FakeSecureKeyGateway(),
              sessionController: sessionController,
              pinStateController: pinStateController,
              sessionKeyStore: DatabaseSessionKeyStore(),
              database: FakeAppDatabase(),
              logger: const AppLogger(),
              appIsForeground: () => true,
            ),
          ),
        ],
        child: const MaterialApp(home: AppLockGate(child: Placeholder())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('使用生物识别解锁'), findsOneWidget);
    expect(find.text('设置应用 PIN'), findsNothing);
    expect(find.text('使用应用 PIN 解锁'), findsNothing);
  });

  testWidgets('unprovisioned lock screen provisions with system auth', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final secureKeyGateway = _FakeSecureKeyGateway(
      status: NativeSecurityStatus.unprovisioned,
    );
    final orchestrator = SecurityOrchestrator(
      biometricGateway: _FakeBiometricGateway(),
      screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
      secureKeyGateway: secureKeyGateway,
      sessionController: sessionController,
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: FakeAppDatabase(),
      logger: const AppLogger(),
      appIsForeground: () => true,
    );
    var unlocked = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWithValue(orchestrator),
        ],
        child: MaterialApp(
          home: AppLockScreen(
            securityState: const NativeSecurityState(
              status: NativeSecurityStatus.unprovisioned,
              keyId: null,
              pinConfigured: false,
              deviceCredentialAvailable: true,
              strongBiometricAvailable: true,
              securityLevel: KeySecurityLevel.unknown,
            ),
            onUnlocked: () => unlocked = true,
          ),
        ),
      ),
    );

    expect(find.text('启用安全存储'), findsOneWidget);
    expect(find.text('使用系统凭据启用'), findsOneWidget);

    await tester.tap(find.text('使用系统凭据启用'));
    await tester.pumpAndSettle();

    expect(secureKeyGateway.provisionCalls, 1);
    expect(sessionController.isUnlocked, isTrue);
    expect(unlocked, isTrue);
  });

  testWidgets('legacy migration starts only after explicit verification', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final secureKeyGateway = _FakeSecureKeyGateway(
      status: NativeSecurityStatus.legacyMigrationRequired,
    );
    final migration = _FakeLegacySecurityMigration(
      onStart: () {
        secureKeyGateway.status = NativeSecurityStatus.locked;
        secureKeyGateway.pinConfigured = true;
      },
    );
    final orchestrator = SecurityOrchestrator(
      biometricGateway: _FakeBiometricGateway(),
      screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
      secureKeyGateway: secureKeyGateway,
      sessionController: sessionController,
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: FakeAppDatabase(),
      logger: const AppLogger(),
      appIsForeground: () => true,
      legacySecurityMigration: migration,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWithValue(orchestrator),
        ],
        child: const MaterialApp(home: AppLockGate(child: Placeholder())),
      ),
    );
    await tester.pumpAndSettle();

    expect(migration.calls, 0);
    expect(find.text('需要升级安全存储'), findsOneWidget);
    expect(find.text('验证并升级安全存储'), findsOneWidget);

    await tester.tap(find.text('验证并升级安全存储'));
    await tester.pumpAndSettle();

    expect(migration.calls, 1);
    expect(find.text('使用生物识别解锁'), findsOneWidget);
    expect(sessionController.isUnlocked, isFalse);
    expect(pinStateController.state.enabled, isTrue);
  });

  testWidgets('a provisioned gate uses system unlock after the next lock', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final database = FakeAppDatabase();
    final secureKeyGateway = _FakeSecureKeyGateway(
      status: NativeSecurityStatus.unprovisioned,
    );
    final orchestrator = SecurityOrchestrator(
      biometricGateway: _FakeBiometricGateway(),
      screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
      secureKeyGateway: secureKeyGateway,
      sessionController: sessionController,
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: database,
      logger: const AppLogger(),
      appIsForeground: () => true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          appDatabaseProvider.overrideWithValue(database),
          securityOrchestratorProvider.overrideWithValue(orchestrator),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Text('sensitive child')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('使用系统凭据启用'));
    await tester.pumpAndSettle();
    expect(find.text('sensitive child'), findsOneWidget);

    await orchestrator.lock();
    await tester.pumpAndSettle();

    expect(find.text('使用生物识别解锁'), findsOneWidget);
    expect(find.text('使用系统凭据启用'), findsNothing);
    expect(secureKeyGateway.provisionCalls, 1);
  });
}
