import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/security_settings_repository.dart';
import 'package:note_secret_search/features/settings/presentation/pin_setup_page.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('pin setup launched from lock flow returns true after successful save', (tester) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository();
    bool? result;

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
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const PinSetupPage(unlockOnSuccess: true),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '1234');
    await tester.enterText(find.byType(TextFormField).last, '1234');
    await tester.tap(find.text('保存 PIN'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(sessionController.state.isUnlocked, isTrue);
  });

  testWidgets('pin setup can save successfully even when settings repository becomes ready later', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    bool? result;

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
          sharedPreferencesProvider.overrideWith((ref) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return SharedPreferences.getInstance();
          }),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const PinSetupPage(unlockOnSuccess: true),
                      ),
                    );
                  },
                  child: const Text('open delayed'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open delayed'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '1234');
    await tester.enterText(find.byType(TextFormField).last, '1234');
    await tester.tap(find.text('保存 PIN'));
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(sessionController.state.isUnlocked, isTrue);
  });
}

class _FakeSecuritySettingsRepository implements SecuritySettingsRepository {
  SecuritySettings _settings = const SecuritySettings.defaults();
  String _pin = '';

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
