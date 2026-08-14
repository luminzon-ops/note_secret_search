import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/domain/security_settings_repository.dart';
import 'package:note_secret_search/features/settings/presentation/pin_setup_page.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';

import '../../../support/fake_app_database.dart';
import '../../../support/widget_test_helpers.dart';

void main() {
  testWidgets('pin setup never unlocks a locked session after save', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository();
    final secureKeyGateway = _FakeSecureKeyGateway();
    bool? result;

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
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const PinSetupPage()),
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

    await tester.enterText(_pinField('输入 4-8 位 PIN'), '1234');
    await tester.enterText(_pinField('确认 PIN'), '1234');
    await tester.tap(find.text('保存 PIN'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(sessionController.state.isUnlocked, isFalse);
    expect(sessionController.state.pinEnabled, isTrue);
    expect(secureKeyGateway.lastConfiguredPin, '1234');
  });

  testWidgets('pin setup waits for lazy settings load before enabling save', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final repository = _FakeSecuritySettingsRepository()
      ..pendingLoad = Completer<SecuritySettings>();
    final secureKeyGateway = _FakeSecureKeyGateway();
    bool? result;

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
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const PinSetupPage()),
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
    await pumpUntilFound(tester, find.text('保存 PIN'));

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存 PIN'),
    );
    expect(saveButton.onPressed, isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    repository.pendingLoad!.complete(repository.settings);
    await tester.pumpAndSettle();
    await tester.enterText(_pinField('输入 4-8 位 PIN'), '1234');
    await tester.enterText(_pinField('确认 PIN'), '1234');
    await tester.tap(find.text('保存 PIN'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(sessionController.state.isUnlocked, isFalse);
    expect(sessionController.state.pinEnabled, isTrue);
    expect(secureKeyGateway.lastConfiguredPin, '1234');
  });
}

Finder _pinField(String labelText) {
  return find.ancestor(
    of: find.text(labelText),
    matching: find.byType(TextFormField),
  );
}

class _FakeSecuritySettingsRepository implements SecuritySettingsRepository {
  SecuritySettings _settings = const SecuritySettings.defaults();
  Completer<SecuritySettings>? pendingLoad;

  SecuritySettings get settings => _settings;

  @override
  Future<SecuritySettings> load() async {
    return pendingLoad?.future ?? _settings;
  }

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
  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {}
}

class _FakeSecureKeyGateway implements SecureKeyGateway {
  String? lastConfiguredPin;
  bool pinConfigured = false;

  @override
  Future<void> configurePin({required String pin}) async {
    lastConfiguredPin = pin;
    pinConfigured = true;
  }

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
  Future<void> removePin() async {
    pinConfigured = false;
  }

  @override
  Future<NativeUnlockResult> unlockWithPin({required String pin}) async {
    return NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List(32),
      fieldKey: Uint8List(32),
      unlockMethod: 'pin',
    );
  }

  @override
  Future<void> rebindSystemAuthWithPin({required String pin}) async {}
}
