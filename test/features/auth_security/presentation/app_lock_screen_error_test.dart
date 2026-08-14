import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';

import '../../../support/fake_app_database.dart';

void main() {
  testWidgets('biometric cancellation stays locked without an uncaught error', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final orchestrator = SecurityOrchestrator(
      biometricGateway: _UnusedBiometricGateway(),
      screenshotProtectionGateway: _ScreenshotGateway(),
      secureKeyGateway: _CancellingSecureKeyGateway(),
      sessionController: sessionController,
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: FakeAppDatabase(),
      logger: const AppLogger(),
      appUnlockVisibility: () => AppUnlockVisibility.foreground,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith((ref) => orchestrator),
        ],
        child: const MaterialApp(
          home: AppLockScreen(onUnlocked: _unexpectedUnlock),
        ),
      ),
    );

    await tester.tap(find.text('使用生物识别解锁'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(sessionController.isUnlocked, isFalse);
    expect(find.text('身份验证已取消'), findsOneWidget);
  });

  testWidgets('unexpected biometric failure restores the unlock action', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final orchestrator = SecurityOrchestrator(
      biometricGateway: _UnusedBiometricGateway(),
      screenshotProtectionGateway: _ScreenshotGateway(),
      secureKeyGateway: _UnexpectedSecureKeyGateway(),
      sessionController: sessionController,
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: FakeAppDatabase(),
      logger: const AppLogger(),
      appUnlockVisibility: () => AppUnlockVisibility.foreground,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith((ref) => orchestrator),
        ],
        child: const MaterialApp(
          home: AppLockScreen(onUnlocked: _unexpectedUnlock),
        ),
      ),
    );

    await tester.tap(find.text('使用生物识别解锁'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('身份验证失败，请重试'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(sessionController.isUnlocked, isFalse);
  });

  testWidgets('rejected biometric result shows a retryable error', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final orchestrator = SecurityOrchestrator(
      biometricGateway: _UnusedBiometricGateway(),
      screenshotProtectionGateway: _ScreenshotGateway(),
      secureKeyGateway: _SuccessfulSecureKeyGateway(),
      sessionController: sessionController,
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: FakeAppDatabase(),
      logger: const AppLogger(),
      appUnlockVisibility: () => AppUnlockVisibility.background,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith((ref) => orchestrator),
        ],
        child: const MaterialApp(
          home: AppLockScreen(onUnlocked: _unexpectedUnlock),
        ),
      ),
    );

    await tester.tap(find.text('使用生物识别解锁'));
    await tester.pumpAndSettle();

    expect(find.text('身份验证失败，请重试'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(sessionController.isUnlocked, isFalse);
  });

  testWidgets('rejected provisioning result shows a retryable error', (
    tester,
  ) async {
    final sessionController = LockSessionController();
    final pinStateController = PinStateController();
    final orchestrator = SecurityOrchestrator(
      biometricGateway: _UnusedBiometricGateway(),
      screenshotProtectionGateway: _ScreenshotGateway(),
      secureKeyGateway: _SuccessfulSecureKeyGateway(),
      sessionController: sessionController,
      pinStateController: pinStateController,
      sessionKeyStore: DatabaseSessionKeyStore(),
      database: FakeAppDatabase(),
      logger: const AppLogger(),
      appUnlockVisibility: () => AppUnlockVisibility.background,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => sessionController,
          ),
          pinStateControllerProvider.overrideWith((ref) => pinStateController),
          securityOrchestratorProvider.overrideWith((ref) => orchestrator),
        ],
        child: const MaterialApp(
          home: AppLockScreen(
            securityState: NativeSecurityState(
              status: NativeSecurityStatus.unprovisioned,
              keyId: null,
              pinConfigured: false,
              deviceCredentialAvailable: true,
              strongBiometricAvailable: true,
              securityLevel: KeySecurityLevel.unknown,
            ),
            onUnlocked: _unexpectedUnlock,
          ),
        ),
      ),
    );

    await tester.tap(find.text('使用系统凭据启用'));
    await tester.pumpAndSettle();

    expect(find.text('安全存储启用失败，请重试'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(sessionController.isUnlocked, isFalse);
  });
}

void _unexpectedUnlock() {
  throw StateError('Cancellation must not unlock the session.');
}

class _CancellingSecureKeyGateway implements SecureKeyGateway {
  @override
  Future<NativeUnlockResult> unlockWithSystemAuth() {
    throw const NativeSecurityException(
      code: 'AUTH_CANCELLED',
      message: 'Authentication was cancelled.',
      details: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnexpectedSecureKeyGateway implements SecureKeyGateway {
  @override
  Future<NativeUnlockResult> unlockWithSystemAuth() {
    throw StateError('unexpected platform bridge failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SuccessfulSecureKeyGateway implements SecureKeyGateway {
  @override
  Future<NativeUnlockResult> provisionWithSystemAuth() =>
      unlockWithSystemAuth();

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedBiometricGateway implements BiometricGateway {
  @override
  Future<bool> authenticate() async => false;

  @override
  Future<BiometricAvailability> getAvailability() async {
    return BiometricAvailability.available;
  }
}

class _ScreenshotGateway implements ScreenshotProtectionGateway {
  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {}
}
