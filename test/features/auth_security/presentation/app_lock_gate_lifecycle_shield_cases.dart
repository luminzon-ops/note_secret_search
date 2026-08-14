part of 'app_lock_gate_test.dart';

void _registerAppLockLifecycleShieldCases() {
  testWidgets('unlocked session stays gated while database is locked', (
    tester,
  ) async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          appDatabaseProvider.overrideWithValue(FakeAppDatabase()),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Text('sensitive child')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('sensitive child'), findsNothing);
    expect(find.text('应用已锁定'), findsOneWidget);
  });

  testWidgets('locked gate reveals the lock screen after its first frame', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final screenshotGateway = _FakeScreenshotProtectionGateway();
    final router = GoRouter(
      initialLocation: '/vault',
      routes: [
        GoRoute(
          path: '/vault',
          builder: (context, state) =>
              const Scaffold(body: Text('sensitive vault content')),
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
          screenshotProtectionGatewayProvider.overrideWithValue(
            screenshotGateway,
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

    expect(find.text('应用已锁定'), findsOneWidget);
    expect(find.text('sensitive vault content'), findsNothing);
    expect(screenshotGateway.obscuredUpdates, [false]);

    pinStateController.configureEnabled(false);
    await tester.pumpAndSettle();
    expect(screenshotGateway.obscuredUpdates, [false]);

    sessionController.lock();
    await tester.pumpAndSettle();
    expect(screenshotGateway.obscuredUpdates, [false, false]);
  });

  testWidgets('locked gate retries a failed safe-surface reveal', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    var revealCalls = 0;
    final screenshotGateway = _FakeScreenshotProtectionGateway(
      onUpdate: (obscured) async {
        if (!obscured) {
          revealCalls += 1;
          if (revealCalls == 1) {
            throw StateError('temporary shield failure');
          }
        }
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          screenshotProtectionGatewayProvider.overrideWithValue(
            screenshotGateway,
          ),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Text('sensitive child')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('应用已锁定'), findsOneWidget);
    expect(find.text('sensitive child'), findsNothing);
    expect(screenshotGateway.obscuredUpdates, [false, false]);
  });

  testWidgets('locked gate keeps the shield while the app is inactive', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final screenshotGateway = _FakeScreenshotProtectionGateway();
    final router = GoRouter(
      initialLocation: '/vault',
      routes: [
        GoRoute(
          path: '/vault',
          builder: (context, state) =>
              const Scaffold(body: Text('sensitive vault content')),
        ),
      ],
    );
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      router.dispose();
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          screenshotProtectionGatewayProvider.overrideWithValue(
            screenshotGateway,
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

    expect(find.text('应用已锁定'), findsOneWidget);
    expect(find.text('sensitive vault content'), findsNothing);
    expect(screenshotGateway.obscuredUpdates, isEmpty);
  });

  testWidgets(
    'locked gate re-obscures when the app becomes inactive during reveal',
    (tester) async {
      final sessionController = LockSessionController();
      final pinStateController = PinStateController();
      final revealBlocker = Completer<void>();
      final screenshotGateway = _FakeScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          if (!obscured) {
            await revealBlocker.future;
          }
        },
      );
      final router = GoRouter(
        initialLocation: '/vault',
        routes: [
          GoRoute(
            path: '/vault',
            builder: (context, state) =>
                const Scaffold(body: Text('sensitive vault content')),
          ),
        ],
      );
      addTearDown(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        router.dispose();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lockSessionControllerProvider.overrideWith(
              (ref) => sessionController,
            ),
            pinStateControllerProvider.overrideWith(
              (ref) => pinStateController,
            ),
            screenshotProtectionGatewayProvider.overrideWithValue(
              screenshotGateway,
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
      await tester.pump();
      expect(screenshotGateway.obscuredUpdates, [false]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      revealBlocker.complete();
      await tester.pumpAndSettle();

      expect(screenshotGateway.obscuredUpdates, [false, true]);
      expect(sessionController.state.isUnlocked, isFalse);
    },
  );

  testWidgets(
    'cancelled system auth reveals the safe lock screen after resume',
    (tester) async {
      final sessionController = LockSessionController();
      final pinStateController = PinStateController();
      final screenshotGateway = _FakeScreenshotProtectionGateway();
      final authentication = Completer<NativeUnlockResult>();
      final secureKeyGateway = _FakeSecureKeyGateway(
        systemUnlockFuture: authentication.future,
      );
      final database = FakeAppDatabase();
      final orchestrator = SecurityOrchestrator(
        biometricGateway: _FakeBiometricGateway(),
        screenshotProtectionGateway: screenshotGateway,
        secureKeyGateway: secureKeyGateway,
        sessionController: sessionController,
        pinStateController: pinStateController,
        sessionKeyStore: DatabaseSessionKeyStore(),
        database: database,
        logger: const AppLogger(),
        appUnlockVisibility: () => AppUnlockVisibility.foreground,
      );
      addTearDown(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      });

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
            securityOrchestratorProvider.overrideWithValue(orchestrator),
            screenshotProtectionGatewayProvider.overrideWithValue(
              screenshotGateway,
            ),
          ],
          child: const MaterialApp(
            home: AppLockGate(child: Text('sensitive child')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(screenshotGateway.obscuredUpdates, [false]);

      await tester.tap(find.text('使用生物识别解锁'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await screenshotGateway.updateRecentTaskProtection(obscured: true);
      authentication.completeError(
        const NativeSecurityException(
          code: 'AUTH_CANCELLED',
          message: null,
          details: null,
        ),
      );
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('应用已锁定'), findsOneWidget);
      expect(find.text('身份验证已取消'), findsOneWidget);
      expect(screenshotGateway.obscuredUpdates, [false, true, false]);
      expect(sessionController.isUnlocked, isFalse);
    },
  );
}
