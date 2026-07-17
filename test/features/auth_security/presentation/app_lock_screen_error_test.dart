import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lock_gate.dart';

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
      logger: const AppLogger(),
      appIsForeground: () => true,
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
