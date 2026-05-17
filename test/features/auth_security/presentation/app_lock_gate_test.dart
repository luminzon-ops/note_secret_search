import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';
import 'package:note_secret_search/features/auth_security/presentation/pin_unlock_page.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/security_settings_repository.dart';
import 'package:note_secret_search/features/settings/presentation/pin_setup_page.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first install lock screen shows biometric and setup pin actions together', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith((ref) => sessionController),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith(
            (ref) => SecurityOrchestrator(
              biometricGateway: _FakeBiometricGateway(),
              screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
              secureKeyGateway: _FakeSecureKeyGateway(),
              sessionController: sessionController,
              pinStateController: pinStateController,
              logger: const AppLogger(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Placeholder()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('使用生物识别解锁'), findsOneWidget);
    expect(find.text('设置应用 PIN'), findsOneWidget);
    expect(find.text('使用应用 PIN 解锁'), findsNothing);
  });

  testWidgets('existing pin lock screen shows biometric and pin unlock actions', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();

    sessionController.setPinEnabled(true);
    pinStateController.configureEnabled(true);
    pinStateController.markPinMaterialReady();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith((ref) => sessionController),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith(
            (ref) => SecurityOrchestrator(
              biometricGateway: _FakeBiometricGateway(),
              screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
              secureKeyGateway: _FakeSecureKeyGateway(),
              sessionController: sessionController,
              pinStateController: pinStateController,
              logger: const AppLogger(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Placeholder()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('使用生物识别解锁'), findsOneWidget);
    expect(find.text('使用应用 PIN 解锁'), findsOneWidget);
    expect(find.text('设置应用 PIN'), findsNothing);
  });

  testWidgets('cold start lock screen restores saved pin state from shared preferences', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flutter.security.pin_enabled': true,
      'flutter.security.pin_material': '2468',
      'flutter.security.biometric_preferred': true,
      'flutter.security.auto_lock_seconds': 30,
      'flutter.security.clipboard_clear_seconds': 60,
    });

    final sessionController = LockSessionController();
    final pinStateController = PinStateController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith((ref) => sessionController),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith(
            (ref) => SecurityOrchestrator(
              biometricGateway: _FakeBiometricGateway(),
              screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
              secureKeyGateway: _FakeSecureKeyGateway(),
              sessionController: sessionController,
              pinStateController: pinStateController,
              logger: const AppLogger(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Placeholder()),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('使用应用 PIN 解锁'), findsOneWidget);
    expect(find.text('设置应用 PIN'), findsNothing);
  });

  testWidgets('existing pin unlock from lock screen returns to vault without navigation error', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository(pin: '2468');
    final router = GoRouter(
      initialLocation: '/vault',
      routes: [
        GoRoute(
          path: '/unlock/pin',
          builder: (context, state) => const PinUnlockPage(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => Scaffold(body: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/vault',
                  builder: (context, state) => const Scaffold(body: Text('vault')),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          lockSessionControllerProvider.overrideWith((ref) => sessionController),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith(
            (ref) => SecurityOrchestrator(
              biometricGateway: _FakeBiometricGateway(),
              screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
              secureKeyGateway: _FakeSecureKeyGateway(),
              sessionController: sessionController,
              pinStateController: pinStateController,
              logger: const AppLogger(),
            ),
          ),
          securitySettingsRepositoryProvider.overrideWith((ref) async => repository),
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
          builder: (context, child) => AppLockGate(
            child: child ?? const SizedBox.shrink(),
          ),
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
    expect(find.text('vault'), findsOneWidget);
  });

  testWidgets('router builder structure reveals pin setup route instead of re-showing lock screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final router = GoRouter(
      initialLocation: '/vault',
      routes: [
        GoRoute(
          path: '/vault',
          builder: (context, state) => const Scaffold(body: Text('vault')),
        ),
        GoRoute(
          path: '/unlock/pin/setup',
          builder: (context, state) => const PinSetupPage(unlockOnSuccess: true),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          lockSessionControllerProvider.overrideWith((ref) => sessionController),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith(
            (ref) => SecurityOrchestrator(
              biometricGateway: _FakeBiometricGateway(),
              screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
              secureKeyGateway: _FakeSecureKeyGateway(),
              sessionController: sessionController,
              pinStateController: pinStateController,
              logger: const AppLogger(),
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppLockGate(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('设置应用 PIN'));
    await tester.pumpAndSettle();

    expect(find.text('输入 4-8 位 PIN'), findsOneWidget);
    expect(find.text('确认 PIN'), findsOneWidget);
    expect(find.text('应用已锁定'), findsNothing);
  });

  testWidgets('lock flow can finish pin setup through dedicated unlock route when repository becomes ready later', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final router = GoRouter(
      initialLocation: '/vault',
      routes: [
        GoRoute(
          path: '/vault',
          builder: (context, state) => const Scaffold(body: Text('vault')),
        ),
        GoRoute(
          path: '/unlock/pin/setup',
          builder: (context, state) => const PinSetupPage(unlockOnSuccess: true),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          lockSessionControllerProvider.overrideWith((ref) => sessionController),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith(
            (ref) => SecurityOrchestrator(
              biometricGateway: _FakeBiometricGateway(),
              screenshotProtectionGateway: _FakeScreenshotProtectionGateway(),
              secureKeyGateway: _FakeSecureKeyGateway(),
              sessionController: sessionController,
              pinStateController: pinStateController,
              logger: const AppLogger(),
            ),
          ),
          sharedPreferencesProvider.overrideWith((ref) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return SharedPreferences.getInstance();
          }),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppLockGate(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('设置应用 PIN'));
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '1234');
    await tester.enterText(find.byType(TextFormField).last, '1234');
    await tester.tap(find.text('保存 PIN'));
    await tester.pumpAndSettle();

    expect(find.text('vault'), findsOneWidget);
    expect(sessionController.state.isUnlocked, isTrue);
  });
}

class _FakeBiometricGateway implements BiometricGateway {
  @override
  Future<bool> authenticate() async => false;

  @override
  Future<BiometricAvailability> getAvailability() async => BiometricAvailability.available;
}

class _FakeScreenshotProtectionGateway implements ScreenshotProtectionGateway {
  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {}
}

class _FakeSecureKeyGateway implements SecureKeyGateway {
  @override
  Future<void> ensureRootKey() async {}

  @override
  Future<String> getDatabasePasswordMaterial() async => 'material';
}

class _FakeSecuritySettingsRepository implements SecuritySettingsRepository {
  _FakeSecuritySettingsRepository({required String pin}) : _pin = pin;

  SecuritySettings _settings = const SecuritySettings.defaults().copyWith(pinEnabled: true);
  String _pin;

  @override
  Future<bool> hasPinMaterial() async => _pin.isNotEmpty;

  @override
  Future<SecuritySettings> load() async => _settings;

  @override
  Future<int> loadAutoLockSeconds() async => _settings.autoLockSeconds;

  @override
  Future<void> save(SecuritySettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> savePinMaterial(String pin) async {
    _pin = pin;
  }

  @override
  Future<bool> verifyPin(String pin) async => _pin == pin;
}
