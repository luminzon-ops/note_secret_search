import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/security_settings_repository.dart';
import 'package:note_secret_search/features/settings/presentation/pin_setup_page.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';

void main() {
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
          appRouterProvider.overrideWithValue(router),
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
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
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
          appRouterProvider.overrideWithValue(router),
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
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
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
            appRouterProvider.overrideWithValue(router),
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
            builder: (context, child) =>
                AppLockGate(child: child ?? const SizedBox.shrink()),
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
              logger: const AppLogger(),
              appIsForeground: () => true,
            ),
          ),
        ],
        child: const MaterialApp(home: AppLockGate(child: Placeholder())),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('使用应用 PIN 解锁'), findsOneWidget);
    expect(find.text('设置应用 PIN'), findsNothing);
  });

  testWidgets('all locked protected routes redirect to vault', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securitySettingsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(
              routerConfig: router,
              builder: (context, child) =>
                  AppLockGate(child: child ?? const SizedBox.shrink()),
            );
          },
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

      expect(
        router.routeInformationProvider.value.uri.path,
        '/vault',
        reason: '$location must be inaccessible while locked',
      );
      expect(find.text('应用已锁定'), findsOneWidget);
      expect(find.text('设置应用 PIN'), findsNothing);
    }
  });

  testWidgets('locked pin route requires enabled pin material', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securitySettingsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(
              routerConfig: router,
              builder: (context, child) =>
                  AppLockGate(child: child ?? const SizedBox.shrink()),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    router.go('/unlock/pin');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/vault');
    expect(find.text('PIN 解锁'), findsNothing);
    expect(find.text('应用已锁定'), findsOneWidget);
  });

  testWidgets('pin state refresh revokes an open unlock route', (tester) async {
    final sessionController = LockSessionController()..setPinEnabled(true);
    final pinStateController = PinStateController()
      ..configureEnabled(true)
      ..markPinMaterialReady();
    final repository = _FakeSecuritySettingsRepository();
    late GoRouter router;

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
              logger: const AppLogger(),
              appIsForeground: () => true,
            ),
          ),
          securitySettingsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(
              routerConfig: router,
              builder: (context, child) =>
                  AppLockGate(child: child ?? const SizedBox.shrink()),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    router.go('/unlock/pin');
    await tester.pumpAndSettle();
    expect(find.text('PIN 解锁'), findsOneWidget);

    sessionController.setPinEnabled(false);
    pinStateController.configureEnabled(false);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/vault');
    expect(find.text('PIN 解锁'), findsNothing);
    expect(find.text('应用已锁定'), findsOneWidget);
  });

  testWidgets(
    'real router pin unlock returns to vault without navigation error',
    (tester) async {
      final sessionController = LockSessionController();
      final pinStateController = PinStateController();
      final repository = _FakeSecuritySettingsRepository();
      late GoRouter router;

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
                logger: const AppLogger(),
                appIsForeground: () => true,
              ),
            ),
            securitySettingsRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            securitySettingsControllerProvider.overrideWith(
              (ref) => SecuritySettingsController(
                repository: repository,
                securityOrchestrator: ref.read(securityOrchestratorProvider),
                pinStateController: pinStateController,
              ),
            ),
            defaultVaultProvider.overrideWith((ref) async => null),
            secretListProvider.overrideWith((ref) async => const []),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              router = ref.watch(appRouterProvider);
              return MaterialApp.router(
                routerConfig: router,
                builder: (context, child) =>
                    AppLockGate(child: child ?? const SizedBox.shrink()),
              );
            },
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
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
      expect(router.routeInformationProvider.value.uri.path, '/vault');
      expect(find.text('保险库'), findsWidgets);
    },
  );

  testWidgets('unlocked session can open pin setup from security settings', (
    tester,
  ) async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository();
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
          appRouterProvider.overrideWithValue(router),
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securitySettingsRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );

    await tester.pumpAndSettle();
    router.go('/settings/security/pin');
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/settings/security/pin',
    );
    expect(find.text('输入 4-8 位 PIN'), findsOneWidget);
    expect(find.text('确认 PIN'), findsOneWidget);
    expect(find.text('应用已锁定'), findsNothing);
    expect(sessionController.state.isUnlocked, isTrue);
  });
}

class _FakeBiometricGateway implements BiometricGateway {
  @override
  Future<bool> authenticate() async => false;

  @override
  Future<BiometricAvailability> getAvailability() async =>
      BiometricAvailability.available;
}

class _FakeScreenshotProtectionGateway implements ScreenshotProtectionGateway {
  _FakeScreenshotProtectionGateway({this.onUpdate});

  final Future<void> Function(bool obscured)? onUpdate;
  final List<bool> obscuredUpdates = [];

  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {
    obscuredUpdates.add(obscured);
    await onUpdate?.call(obscured);
  }
}

class _FakeSecureKeyGateway implements SecureKeyGateway {
  _FakeSecureKeyGateway({this.pinConfigured = false});

  bool pinConfigured;

  @override
  Future<void> configurePin({required String pin}) async {
    pinConfigured = true;
  }

  @override
  Future<void> ensureRootKey() async {}

  @override
  Future<String> getDatabasePasswordMaterial() async => 'material';

  @override
  Future<NativeSecurityState> getSecurityState() async {
    return NativeSecurityState(
      status: NativeSecurityStatus.locked,
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      pinConfigured: pinConfigured,
      deviceCredentialAvailable: true,
      strongBiometricAvailable: true,
      securityLevel: KeySecurityLevel.tee,
    );
  }

  @override
  Future<NativeUnlockResult> unlockWithSystemAuth() async {
    return NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List(32),
      fieldKey: Uint8List(32),
      unlockMethod: 'system',
    );
  }

  @override
  Future<void> removePin() async {
    pinConfigured = false;
  }

  @override
  Future<NativeUnlockResult> unlockWithPin({required String pin}) async {
    if (pin != '2468') {
      throw const NativeSecurityException(
        code: 'PIN_INCORRECT',
        message: null,
        details: null,
      );
    }
    return NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List(32),
      fieldKey: Uint8List(32),
      unlockMethod: 'pin',
    );
  }
}

class _FakeSecuritySettingsRepository implements SecuritySettingsRepository {
  SecuritySettings _settings = const SecuritySettings.defaults().copyWith(
    pinEnabled: true,
  );

  @override
  Future<SecuritySettings> load() async => _settings;

  @override
  Future<int> loadAutoLockSeconds() async => _settings.autoLockSeconds;

  @override
  Future<void> save(SecuritySettings settings) async {
    _settings = settings;
  }
}
