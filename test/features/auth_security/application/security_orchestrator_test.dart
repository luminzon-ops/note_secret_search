import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';

void main() {
  test(
    'biometric unlock removes the shield before marking session unlocked',
    () async {
      final sessionController = LockSessionController();
      final screenshotGateway = _RecordingScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          expect(obscured, isFalse);
          expect(sessionController.state.isUnlocked, isFalse);
        },
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: screenshotGateway,
      );

      final unlocked = await orchestrator.unlockWithBiometrics();

      expect(unlocked, isTrue);
      expect(screenshotGateway.obscuredUpdates, [false]);
      expect(sessionController.state.isUnlocked, isTrue);
    },
  );

  test('biometric unlock stays locked when shield removal fails', () async {
    final sessionController = LockSessionController();
    final screenshotGateway = _RecordingScreenshotProtectionGateway(
      onUpdate: (_) => Future<void>.error(StateError('shield failed')),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
    );

    final unlocked = await orchestrator.unlockWithBiometrics();

    expect(unlocked, isFalse);
    expect(sessionController.state.isUnlocked, isFalse);
  });

  test(
    'pin unlock waits for shield removal before marking session unlocked',
    () async {
      final sessionController = LockSessionController();
      final shieldBlocker = Completer<void>();
      final screenshotGateway = _RecordingScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          expect(obscured, isFalse);
          expect(sessionController.state.isUnlocked, isFalse);
          await shieldBlocker.future;
        },
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: screenshotGateway,
      );

      unawaited(
        Future<void>(() {
          orchestrator.unlockWithPin();
        }),
      );
      await _waitUntil(() => screenshotGateway.obscuredUpdates.isNotEmpty);

      expect(sessionController.state.isUnlocked, isFalse);

      shieldBlocker.complete();
      await _waitUntil(() => sessionController.state.isUnlocked);

      expect(screenshotGateway.obscuredUpdates, [false]);
    },
  );

  test('pin unlock stays locked when shield removal fails', () async {
    final sessionController = LockSessionController();
    final screenshotGateway = _RecordingScreenshotProtectionGateway(
      onUpdate: (_) => Future<void>.error(StateError('shield failed')),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
    );

    unawaited(
      Future<void>(() {
        orchestrator.unlockWithPin();
      }),
    );
    await _drainEventQueue();

    expect(screenshotGateway.obscuredUpdates, [false]);
    expect(sessionController.state.isUnlocked, isFalse);
  });
}

SecurityOrchestrator _buildOrchestrator({
  required LockSessionController sessionController,
  required ScreenshotProtectionGateway screenshotGateway,
}) {
  return SecurityOrchestrator(
    biometricGateway: _SuccessfulBiometricGateway(),
    screenshotProtectionGateway: screenshotGateway,
    secureKeyGateway: _FakeSecureKeyGateway(),
    sessionController: sessionController,
    pinStateController: PinStateController(),
    logger: const AppLogger(),
  );
}

class _SuccessfulBiometricGateway implements BiometricGateway {
  @override
  Future<bool> authenticate() async => true;

  @override
  Future<BiometricAvailability> getAvailability() async {
    return BiometricAvailability.available;
  }
}

class _RecordingScreenshotProtectionGateway
    implements ScreenshotProtectionGateway {
  _RecordingScreenshotProtectionGateway({this.onUpdate});

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
  @override
  Future<void> ensureRootKey() async {}

  @override
  Future<String> getDatabasePasswordMaterial() async => 'material';
}

Future<void> _drainEventQueue() async {
  for (var index = 0; index < 10; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100; index += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached before the test timeout.');
}
