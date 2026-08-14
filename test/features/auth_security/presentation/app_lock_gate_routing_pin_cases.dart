part of 'app_lock_gate_test.dart';

void _registerAppLockRoutingPinCases() {
  testWidgets(
    'existing pin lock screen shows biometric and pin unlock actions',
    (tester) async {
      final sessionController = LockSessionController();
      final pinStateController = PinStateController();

      sessionController.setPinEnabled(true);
      pinStateController.configureEnabled(true);
      pinStateController.markPinMaterialReady();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lockSessionControllerProvider.overrideWith(
              (ref) => sessionController,
            ),
            pinStateControllerProvider.overrideWith(
              (ref) => pinStateController,
            ),
            securityOrchestratorProvider.overrideWith(
              (ref) => SecurityOrchestrator(
                biometricGateway: _FakeBiometricGateway(),
                screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
                secureKeyGateway: _FakeSecureKeyGateway(pinConfigured: true),
                sessionController: sessionController,
                pinStateController: pinStateController,
                sessionKeyStore: DatabaseSessionKeyStore(),
                database: FakeAppDatabase(),
                logger: const AppLogger(),
                appUnlockVisibility: () => AppUnlockVisibility.foreground,
              ),
            ),
          ],
          child: const MaterialApp(home: AppLockGate(child: Placeholder())),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('使用生物识别解锁'), findsOneWidget);
      expect(find.text('使用应用 PIN 解锁'), findsOneWidget);
      expect(find.text('设置应用 PIN'), findsNothing);
    },
  );

  testWidgets('cold start lock screen restores pin state from native keyring', (
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
              secureKeyGateway: _FakeSecureKeyGateway(pinConfigured: true),
              sessionController: sessionController,
              pinStateController: pinStateController,
              sessionKeyStore: DatabaseSessionKeyStore(),
              database: FakeAppDatabase(),
              logger: const AppLogger(),
              appUnlockVisibility: () => AppUnlockVisibility.foreground,
            ),
          ),
        ],
        child: const MaterialApp(home: AppLockGate(child: Placeholder())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('使用应用 PIN 解锁'), findsOneWidget);
    expect(find.text('设置应用 PIN'), findsNothing);
  });

  testWidgets('all locked protected routes redirect to vault', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository();
    final router = _createTestRouter(
      sessionController: sessionController,
      pinStateController: pinStateController,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securitySettingsRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppLockRouteGate(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    const protectedLocations = <String>[
      '/vault/secret/new',
      '/vault/secret/secret-id',
      '/vault/secret/secret-id/edit',
      '/search',
      '/search/settings',
      '/notes',
      '/notes/item/new',
      '/notes/item/note-id',
      '/notes/item/note-id/edit',
      '/ai/chat',
      '/models',
      '/settings',
      '/settings/security',
      '/settings/security/pin',
      '/settings/ai/providers',
    ];

    for (final location in protectedLocations) {
      router.go(location);
      await tester.pumpAndSettle();

      expect(find.text('应用已锁定'), findsOneWidget);
      expect(
        find.text(location),
        findsNothing,
        reason: '$location must be inaccessible while locked',
      );
      expect(find.text('设置应用 PIN'), findsNothing);
    }
  });

  testWidgets('locked pin route requires enabled pin material', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository();
    final router = _createTestRouter(
      sessionController: sessionController,
      pinStateController: pinStateController,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securitySettingsRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppLockRouteGate(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    router.go('/unlock/pin');
    await tester.pumpAndSettle();

    expect(find.text('PIN 解锁'), findsNothing);
    expect(find.text('应用已锁定'), findsOneWidget);
  });

  testWidgets('pin state refresh revokes an open unlock route', (tester) async {
    final sessionController = LockSessionController()..setPinEnabled(true);
    final pinStateController = PinStateController()
      ..configureEnabled(true)
      ..markPinMaterialReady();
    final repository = _FakeSecuritySettingsRepository();
    final router = _createTestRouter(
      sessionController: sessionController,
      pinStateController: pinStateController,
    );
    addTearDown(router.dispose);

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
              secureKeyGateway: _FakeSecureKeyGateway(pinConfigured: true),
              sessionController: sessionController,
              pinStateController: pinStateController,
              sessionKeyStore: DatabaseSessionKeyStore(),
              database: FakeAppDatabase(),
              logger: const AppLogger(),
              appUnlockVisibility: () => AppUnlockVisibility.foreground,
            ),
          ),
          securitySettingsRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppLockRouteGate(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    router.go('/unlock/pin');
    await tester.pumpAndSettle();
    expect(find.text('PIN 解锁'), findsOneWidget);

    sessionController.setPinEnabled(false);
    pinStateController.configureEnabled(false);
    router.refresh();
    await tester.pumpAndSettle();

    expect(find.text('PIN 解锁'), findsNothing);
    expect(find.text('应用已锁定'), findsOneWidget);
  });

  testWidgets(
    'real router pin unlock returns to vault without navigation error',
    (tester) async {
      final sessionController = LockSessionController();
      final pinStateController = PinStateController();
      final repository = _FakeSecuritySettingsRepository();
      final database = FakeAppDatabase();
      final router = _createTestRouter(
        sessionController: sessionController,
        pinStateController: pinStateController,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lockSessionControllerProvider.overrideWith(
              (ref) => sessionController,
            ),
            pinStateControllerProvider.overrideWith(
              (ref) => pinStateController,
            ),
            appDatabaseProvider.overrideWithValue(database),
            securityOrchestratorProvider.overrideWith(
              (ref) => SecurityOrchestrator(
                biometricGateway: _FakeBiometricGateway(),
                screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
                secureKeyGateway: _FakeSecureKeyGateway(pinConfigured: true),
                sessionController: sessionController,
                pinStateController: pinStateController,
                sessionKeyStore: DatabaseSessionKeyStore(),
                database: database,
                logger: const AppLogger(),
                appUnlockVisibility: () => AppUnlockVisibility.foreground,
              ),
            ),
            securitySettingsRepositoryProvider.overrideWith(
              (ref) => repository,
            ),
            securitySettingsControllerProvider.overrideWith(
              (ref) => SecuritySettingsController(
                repository: repository,
                securityOrchestrator: ref.read(securityOrchestratorProvider),
                pinStateController: pinStateController,
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => AppLockRouteGate(
              router: router,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('使用应用 PIN 解锁'), findsOneWidget);

      await tester.tap(find.text('使用应用 PIN 解锁'));
      await tester.pumpAndSettle();
      expect(find.text('PIN 解锁'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '2468');
      await tester.tap(find.text('解锁'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sessionController.state.isUnlocked, isTrue);
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(visibleText, contains('保险库'));
    },
  );

  testWidgets('unlocked session can open pin setup from security settings', (
    tester,
  ) async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository();
    final database = FakeAppDatabase(
      initialStatus: DatabaseLifecycleStatus.open,
    );
    final orchestrator = SecurityOrchestrator(
      biometricGateway: _FakeBiometricGateway(),
      screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
      secureKeyGateway: _FakeSecureKeyGateway(),
      sessionController: sessionController,
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: database,
      logger: const AppLogger(),
      appUnlockVisibility: () => AppUnlockVisibility.foreground,
    );
    final router = GoRouter(
      initialLocation: '/vault',
      routes: [
        GoRoute(
          path: '/vault',
          builder: (context, state) => const Scaffold(body: Text('vault')),
        ),
        GoRoute(
          path: '/settings/security/pin',
          builder: (context, state) => const PinSetupPage(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          appDatabaseProvider.overrideWithValue(database),
          securitySettingsRepositoryProvider.overrideWith((ref) => repository),
          securitySettingsControllerProvider.overrideWith(
            (ref) => SecuritySettingsController(
              repository: repository,
              securityOrchestrator: orchestrator,
              pinStateController: pinStateController,
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppLockRouteGate(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    router.go('/settings/security/pin');
    await tester.pumpAndSettle();

    expect(find.text('输入 4-8 位 PIN'), findsOneWidget);
    expect(find.text('确认 PIN'), findsOneWidget);
    expect(find.text('应用已锁定'), findsNothing);
    expect(sessionController.state.isUnlocked, isTrue);
  });
}
