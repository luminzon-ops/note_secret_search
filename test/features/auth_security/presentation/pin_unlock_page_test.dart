import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/router/lock_route_guard.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/presentation/pin_unlock_page.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';

import '../../../support/fake_app_database.dart';
import 'package:note_secret_search/features/settings/domain/security_settings_repository.dart';

void main() {
  testWidgets(
    'pin unlock falls back to vault route when opened as top-level route',
    (tester) async {
      final sessionController = LockSessionController();
      final pinStateController = PinStateController()..markPinMaterialReady();
      final repository = _FakeSecuritySettingsRepository();
      final secureKeyGateway = _FakeSecureKeyGateway(pin: '2468');
      sessionController.setPinEnabled(true);
      pinStateController.configureEnabled(true);
      final routeGuard = LockRouteGuard(navigation: PostUnlockNavigation());
      final router = GoRouter(
        initialLocation: '/unlock/pin',
        redirect: (context, state) => routeGuard.redirect(
          session: sessionController.state,
          pinState: pinStateController.state,
          uri: state.uri,
        ),
        routes: [
          GoRoute(
            path: '/unlock/pin',
            builder: (context, state) => const PinUnlockPage(),
          ),
          GoRoute(
            path: '/vault',
            builder: (context, state) =>
                const Scaffold(body: Text('vault home')),
          ),
        ],
      );

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
                secureKeyGateway: secureKeyGateway,
                sessionController: sessionController,
                pinStateController: pinStateController,
                sessionKeyStore: DatabaseSessionKeyStore(),
                database: FakeAppDatabase(),
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
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      final sessionSubscription = sessionController.stream.listen((_) {
        router.refresh();
      });
      addTearDown(() async {
        await sessionSubscription.cancel();
        router.dispose();
      });

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2468');
      await tester.tap(find.text('解锁'));
      await tester.pumpAndSettle();

      expect(sessionController.state.isUnlocked, isTrue);
      expect(find.text('vault home'), findsOneWidget);
    },
  );

  testWidgets('pin unlock succeeds when opened from a parent route', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController()..markPinMaterialReady();
    final repository = _FakeSecuritySettingsRepository();
    final secureKeyGateway = _FakeSecureKeyGateway(pin: '2468');
    bool? result;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await context.push<bool>('/unlock/pin');
                },
                child: const Text('open unlock'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/unlock/pin',
          builder: (context, state) => const PinUnlockPage(),
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
          securityOrchestratorProvider.overrideWith(
            (ref) => SecurityOrchestrator(
              biometricGateway: _FakeBiometricGateway(),
              screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
              secureKeyGateway: secureKeyGateway,
              sessionController: sessionController,
              pinStateController: pinStateController,
              sessionKeyStore: DatabaseSessionKeyStore(),
              database: FakeAppDatabase(),
              logger: const AppLogger(),
              appUnlockVisibility: () => AppUnlockVisibility.foreground,
            ),
          ),
          securitySettingsRepositoryProvider.overrideWith((ref) => repository),
          securitySettingsControllerProvider.overrideWith(
            (ref) => SecuritySettingsController(
              repository: repository,
              securityOrchestrator: ref.read(securityOrchestratorProvider),
              pinStateController: pinStateController,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('open unlock'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '2468');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(sessionController.state.isUnlocked, isTrue);
    expect(result, isTrue);
    expect(find.text('open unlock'), findsOneWidget);
  });

  testWidgets('pin unlock shows error and increments failures for wrong pin', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController()..markPinMaterialReady();
    final repository = _FakeSecuritySettingsRepository();
    final secureKeyGateway = _FakeSecureKeyGateway(pin: '2468');

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
              secureKeyGateway: secureKeyGateway,
              sessionController: sessionController,
              pinStateController: pinStateController,
              sessionKeyStore: DatabaseSessionKeyStore(),
              database: FakeAppDatabase(),
              logger: const AppLogger(),
              appUnlockVisibility: () => AppUnlockVisibility.foreground,
            ),
          ),
          securitySettingsRepositoryProvider.overrideWith((ref) => repository),
          securitySettingsControllerProvider.overrideWith(
            (ref) => SecuritySettingsController(
              repository: repository,
              securityOrchestrator: ref.read(securityOrchestratorProvider),
              pinStateController: pinStateController,
            ),
          ),
        ],
        child: const MaterialApp(home: PinUnlockPage()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '0000');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(find.text('PIN 错误'), findsOneWidget);
    expect(sessionController.state.isUnlocked, isFalse);
  });

  testWidgets('native pin result cannot override a newer lock', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController()..markPinMaterialReady();
    final unlockBlocker = Completer<NativeUnlockResult>();
    final repository = _FakeSecuritySettingsRepository();
    final secureKeyGateway = _FakeSecureKeyGateway(
      pin: '2468',
      unlockResult: unlockBlocker.future,
    );
    final screenshotGateway = _FakeScreenshotProtectionGateway();

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
              screenshotProtectionGateway: screenshotGateway,
              secureKeyGateway: secureKeyGateway,
              sessionController: sessionController,
              pinStateController: pinStateController,
              sessionKeyStore: DatabaseSessionKeyStore(),
              database: FakeAppDatabase(),
              logger: const AppLogger(),
              appUnlockVisibility: () => AppUnlockVisibility.foreground,
            ),
          ),
          securitySettingsRepositoryProvider.overrideWith((ref) => repository),
          securitySettingsControllerProvider.overrideWith(
            (ref) => SecuritySettingsController(
              repository: repository,
              securityOrchestrator: ref.read(securityOrchestratorProvider),
              pinStateController: pinStateController,
            ),
          ),
        ],
        child: const MaterialApp(home: PinUnlockPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '2468');
    await tester.tap(find.text('解锁'));
    await tester.pump();

    sessionController.lock();
    unlockBlocker.complete(_pinUnlockMaterial());
    await tester.pumpAndSettle();

    expect(find.text('安全解锁失败，请重试'), findsOneWidget);
    expect(sessionController.state.isUnlocked, isFalse);
    expect(screenshotGateway.obscuredUpdates, isEmpty);
  });
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

class _FakeBiometricGateway implements BiometricGateway {
  @override
  Future<bool> authenticate() async => false;

  @override
  Future<BiometricAvailability> getAvailability() async =>
      BiometricAvailability.available;
}

class _FakeScreenshotProtectionGateway implements ScreenshotProtectionGateway {
  final List<bool> obscuredUpdates = [];

  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {
    obscuredUpdates.add(obscured);
  }
}

class _FakeSecureKeyGateway implements SecureKeyGateway {
  _FakeSecureKeyGateway({required this.pin, this.unlockResult});

  final String pin;
  final Future<NativeUnlockResult>? unlockResult;

  @override
  Future<void> configurePin({required String pin}) async {}

  @override
  Future<NativeSecurityState> getSecurityState() async {
    return const NativeSecurityState(
      status: NativeSecurityStatus.locked,
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      pinConfigured: true,
      deviceCredentialAvailable: true,
      strongBiometricAvailable: true,
      securityLevel: KeySecurityLevel.tee,
    );
  }

  @override
  Future<NativeUnlockResult> provisionWithSystemAuth() {
    return unlockWithSystemAuth();
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
  Future<void> removePin() async {}

  @override
  Future<NativeUnlockResult> unlockWithPin({required String pin}) async {
    if (pin != this.pin) {
      throw const NativeSecurityException(
        code: 'PIN_INCORRECT',
        message: null,
        details: null,
      );
    }
    return await (unlockResult ??
        Future<NativeUnlockResult>.value(_pinUnlockMaterial()));
  }

  @override
  Future<void> rebindSystemAuthWithPin({required String pin}) async {}
}

NativeUnlockResult _pinUnlockMaterial() {
  return NativeUnlockResult(
    keyId: '123e4567-e89b-42d3-a456-426614174000',
    databaseKey: Uint8List(32),
    fieldKey: Uint8List(32),
    unlockMethod: 'pin',
  );
}
