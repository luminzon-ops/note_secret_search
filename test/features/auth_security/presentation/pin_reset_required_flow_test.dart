import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/security_settings_repository.dart';

import '../../../support/fake_app_database.dart';

void main() {
  testWidgets(
    'system unlock routes a corrupt pin envelope directly to pin replacement',
    (tester) async {
      final sessionController = LockSessionController();
      final pinStateController = PinStateController();
      final database = FakeAppDatabase();
      final secureKeyGateway = _PinResetSecureKeyGateway();
      final settingsRepository = _SecuritySettingsRepository();
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
            appDatabaseProvider.overrideWithValue(database),
            securityOrchestratorProvider.overrideWith(
              (ref) => SecurityOrchestrator(
                biometricGateway: const _BiometricGateway(),
                screenshotProtectionGateway:
                    const _ScreenshotProtectionGateway(),
                secureKeyGateway: secureKeyGateway,
                sessionController: sessionController,
                pinStateController: pinStateController,
                sessionKeyStore: DatabaseSessionKeyStore(),
                database: database,
                logger: const AppLogger(),
                appIsForeground: () => true,
              ),
            ),
            securitySettingsRepositoryProvider.overrideWith(
              (ref) async => settingsRepository,
            ),
            securitySettingsControllerProvider.overrideWith(
              (ref) => SecuritySettingsController(
                repository: settingsRepository,
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
      await tester.pumpAndSettle();

      expect(find.text('应用 PIN 已损坏，请使用系统认证解锁并立即重新设置。'), findsOneWidget);

      await tester.tap(find.text('使用生物识别解锁'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sessionController.isUnlocked, isTrue);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/settings/security/pin',
      );
      expect(find.text('输入 4-8 位 PIN'), findsOneWidget);
      expect(find.text('确认 PIN'), findsOneWidget);
    },
  );
}

class _PinResetSecureKeyGateway implements SecureKeyGateway {
  @override
  Future<void> configurePin({required String pin}) async {}

  @override
  Future<NativeSecurityState> getSecurityState() async {
    return const NativeSecurityState(
      status: NativeSecurityStatus.locked,
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      pinConfigured: false,
      deviceCredentialAvailable: true,
      strongBiometricAvailable: true,
      securityLevel: KeySecurityLevel.tee,
      pinResetRequired: true,
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
  Future<NativeUnlockResult> provisionWithSystemAuth() =>
      unlockWithSystemAuth();

  @override
  Future<void> rebindSystemAuthWithPin({required String pin}) async {}

  @override
  Future<void> removePin() async {}

  @override
  Future<NativeUnlockResult> unlockWithPin({required String pin}) {
    throw StateError('PIN unlock must remain unavailable until replacement.');
  }
}

class _SecuritySettingsRepository implements SecuritySettingsRepository {
  SecuritySettings _settings = const SecuritySettings.defaults();

  @override
  Future<SecuritySettings> load() async => _settings;

  @override
  Future<int> loadAutoLockSeconds() async => _settings.autoLockSeconds;

  @override
  Future<void> save(SecuritySettings settings) async {
    _settings = settings;
  }
}

class _BiometricGateway implements BiometricGateway {
  const _BiometricGateway();

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<BiometricAvailability> getAvailability() async =>
      BiometricAvailability.available;
}

class _ScreenshotProtectionGateway implements ScreenshotProtectionGateway {
  const _ScreenshotProtectionGateway();

  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {}
}
