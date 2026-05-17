import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/auth_security/presentation/pin_unlock_page.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/security_settings_repository.dart';

void main() {
  testWidgets('pin unlock falls back to vault route when opened as top-level route', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController()..markPinMaterialReady();
    final repository = _FakeSecuritySettingsRepository(pin: '2468');
    final router = GoRouter(
      initialLocation: '/unlock/pin',
      routes: [
        GoRoute(path: '/unlock/pin', builder: (context, state) => const PinUnlockPage()),
        GoRoute(
          path: '/vault',
          builder: (context, state) => const Scaffold(body: Text('vault home')),
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '2468');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(sessionController.state.isUnlocked, isTrue);
    expect(find.text('vault home'), findsOneWidget);
  });

  testWidgets('pin unlock succeeds when opened from a parent route', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController()..markPinMaterialReady();
    final repository = _FakeSecuritySettingsRepository(pin: '2468');
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
        GoRoute(path: '/unlock/pin', builder: (context, state) => const PinUnlockPage()),
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

  testWidgets('pin unlock shows error and increments failures for wrong pin', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController()..markPinMaterialReady();
    final repository = _FakeSecuritySettingsRepository(pin: '2468');

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
          securitySettingsRepositoryProvider.overrideWith((ref) async => repository),
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
