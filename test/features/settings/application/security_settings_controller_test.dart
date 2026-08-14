import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/domain/security_settings_repository.dart';

import '../../../support/fake_app_database.dart';

void main() {
  test('load derives pin availability from native keyring state', () async {
    final gateway = _FakeSecureKeyGateway(pinConfigured: false);
    final repository = _FakeSecuritySettingsRepository(
      settings: const SecuritySettings.defaults().copyWith(pinEnabled: true),
    );
    final pinStateController = PinStateController();
    final controller = _controller(
      gateway: gateway,
      repository: repository,
      pinStateController: pinStateController,
    );

    await controller.load();

    expect(controller.state.asData?.value.pinEnabled, isFalse);
    expect(pinStateController.state.enabled, isFalse);
    expect(pinStateController.state.hasPinMaterial, isFalse);
  });

  test(
    'setPin configures native envelope without persisting pin material',
    () async {
      final gateway = _FakeSecureKeyGateway(pinConfigured: false);
      final repository = _FakeSecuritySettingsRepository();
      final pinStateController = PinStateController();
      final controller = _controller(
        gateway: gateway,
        repository: repository,
        pinStateController: pinStateController,
      );
      await controller.load();

      await controller.setPin('2468');

      expect(gateway.lastConfiguredPin, '2468');
      expect(controller.state.asData?.value.pinEnabled, isTrue);
      expect(pinStateController.state.hasPinMaterial, isTrue);
      expect(repository.savedSettings.single.pinEnabled, isTrue);
    },
  );

  test('disabling pin removes the native envelope', () async {
    final gateway = _FakeSecureKeyGateway(pinConfigured: true);
    final repository = _FakeSecuritySettingsRepository();
    final pinStateController = PinStateController();
    final controller = _controller(
      gateway: gateway,
      repository: repository,
      pinStateController: pinStateController,
    );
    await controller.load();

    await controller.updatePinEnabled(false);

    expect(gateway.removeCalls, 1);
    expect(controller.state.asData?.value.pinEnabled, isFalse);
    expect(pinStateController.state.hasPinMaterial, isFalse);
  });

  test('mutations reject while settings are still loading', () async {
    final gateway = _FakeSecureKeyGateway(pinConfigured: false);
    final repository = _FakeSecuritySettingsRepository()
      ..pendingLoad = Completer<SecuritySettings>();
    final controller = _controller(
      gateway: gateway,
      repository: repository,
      pinStateController: PinStateController(),
    );

    await expectLater(
      controller.updateAutoLockSeconds(60),
      throwsA(isA<StateError>()),
    );

    expect(controller.state, isA<AsyncLoading<SecuritySettings>>());
    expect(repository.savedSettings, isEmpty);
    repository.pendingLoad!.complete(repository.settings);
  });

  test('mutations reject after settings fail to load', () async {
    final gateway = _FakeSecureKeyGateway(pinConfigured: false);
    final repository = _FakeSecuritySettingsRepository()
      ..loadError = StateError('settings unavailable');
    final controller = _controller(
      gateway: gateway,
      repository: repository,
      pinStateController: PinStateController(),
    );

    await _waitForState(controller, (state) => state.hasError);

    await expectLater(
      controller.updateAutoLockSeconds(60),
      throwsA(isA<StateError>()),
    );
    expect(repository.savedSettings, isEmpty);
  });

  test('late load completion is ignored after controller disposal', () async {
    final gateway = _FakeSecureKeyGateway(pinConfigured: false);
    final repository = _FakeSecuritySettingsRepository();
    final controller = _controller(
      gateway: gateway,
      repository: repository,
      pinStateController: PinStateController(),
    );
    await _waitForState(controller, (state) => state.hasValue);

    repository.pendingLoad = Completer<SecuritySettings>();
    final pendingLoad = controller.load();
    controller.dispose();
    repository.pendingLoad!.complete(repository.settings);

    await expectLater(pendingLoad, completes);
  });
}

Future<void> _waitForState(
  SecuritySettingsController controller,
  bool Function(AsyncValue<SecuritySettings> state) predicate,
) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (predicate(controller.state)) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Security settings state did not settle.');
}

SecuritySettingsController _controller({
  required _FakeSecureKeyGateway gateway,
  required _FakeSecuritySettingsRepository repository,
  required PinStateController pinStateController,
}) {
  return SecuritySettingsController(
    repository: repository,
    securityOrchestrator: SecurityOrchestrator(
      biometricGateway: _NoopBiometricGateway(),
      screenshotProtectionGateway: _NoopScreenshotProtectionGateway(),
      secureKeyGateway: gateway,
      sessionController: LockSessionController(),
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: FakeAppDatabase(),
      logger: const AppLogger(),
      appUnlockVisibility: () => AppUnlockVisibility.foreground,
    ),
    pinStateController: pinStateController,
  );
}

class _FakeSecuritySettingsRepository implements SecuritySettingsRepository {
  _FakeSecuritySettingsRepository({
    this.settings = const SecuritySettings.defaults(),
  });

  SecuritySettings settings;
  final List<SecuritySettings> savedSettings = <SecuritySettings>[];
  Completer<SecuritySettings>? pendingLoad;
  Object? loadError;

  @override
  Future<SecuritySettings> load() async {
    final pending = pendingLoad;
    if (pending != null) {
      return pending.future;
    }
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return settings;
  }

  @override
  Future<int> loadAutoLockSeconds() async => settings.autoLockSeconds;

  @override
  Future<void> save(SecuritySettings settings) async {
    this.settings = settings;
    savedSettings.add(settings);
  }
}

class _FakeSecureKeyGateway implements SecureKeyGateway {
  _FakeSecureKeyGateway({required this.pinConfigured});

  bool pinConfigured;
  String? lastConfiguredPin;
  int removeCalls = 0;

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
    removeCalls += 1;
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

class _NoopBiometricGateway implements BiometricGateway {
  @override
  Future<bool> authenticate() async => false;

  @override
  Future<BiometricAvailability> getAvailability() async {
    return BiometricAvailability.available;
  }
}

class _NoopScreenshotProtectionGateway implements ScreenshotProtectionGateway {
  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {}
}
