import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
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

  test('biometric unlock installs typed system session keys', () async {
    final sessionKeyStore = DatabaseSessionKeyStore();
    final sessionController = LockSessionController(
      onLock: sessionKeyStore.clear,
    );
    final unlockMaterial = NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List.fromList(List<int>.filled(32, 5)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 6)),
      unlockMethod: 'system',
    );
    final secureKeyGateway = _RecordingSecureKeyGateway(
      systemUnlockResult: unlockMaterial,
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: _RecordingScreenshotProtectionGateway(),
      biometricGateway: _UnexpectedBiometricAuthenticationGateway(),
      secureKeyGateway: secureKeyGateway,
      sessionKeyStore: sessionKeyStore,
    );

    expect(await orchestrator.unlockWithBiometrics(), isTrue);

    expect(secureKeyGateway.systemUnlockCalls, 1);
    expect(
      sessionKeyStore.requireCurrent().withFieldKey(
        (key) => Uint8List.fromList(key),
      ),
      everyElement(6),
    );
    expect(unlockMaterial.isCleared, isTrue);
  });

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

  test('biometric result is discarded after a newer lock epoch', () async {
    final sessionController = LockSessionController();
    final unlockMaterial = NativeUnlockResult(
      keyId: '123e4567-e89b-42d3-a456-426614174000',
      databaseKey: Uint8List.fromList(List<int>.filled(32, 3)),
      fieldKey: Uint8List.fromList(List<int>.filled(32, 4)),
      unlockMethod: 'system',
    );
    final authenticationBlocker = Completer<NativeUnlockResult>();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      systemUnlockFuture: authenticationBlocker.future,
    );
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      secureKeyGateway: secureKeyGateway,
    );

    final unlockFuture = orchestrator.unlockWithBiometrics();
    await _waitUntil(() => secureKeyGateway.systemUnlockCalls == 1);

    sessionController.lock();
    authenticationBlocker.complete(unlockMaterial);

    expect(await unlockFuture, isFalse);
    expect(screenshotGateway.obscuredUpdates, isEmpty);
    expect(sessionController.state.isUnlocked, isFalse);
    expect(unlockMaterial.isCleared, isTrue);
  });

  test(
    'pin unlock waits for shield removal before marking session unlocked',
    () async {
      final sessionController = LockSessionController();
      final unlockMaterial = _pinUnlockMaterial();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        unlockResult: unlockMaterial,
      );
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
        secureKeyGateway: secureKeyGateway,
      );

      unawaited(
        Future<void>(() {
          orchestrator.unlockWithPin(
            pin: '2468',
            expectedLockEpoch: sessionController.state.lockEpoch,
          );
        }),
      );
      await _waitUntil(() => screenshotGateway.obscuredUpdates.isNotEmpty);

      expect(sessionController.state.isUnlocked, isFalse);

      shieldBlocker.complete();
      await _waitUntil(() => sessionController.state.isUnlocked);

      expect(screenshotGateway.obscuredUpdates, [false]);
      expect(secureKeyGateway.lastPin, '2468');
      expect(unlockMaterial.isCleared, isTrue);
    },
  );

  test('pin unlock stays locked when shield removal fails', () async {
    final sessionController = LockSessionController();
    final unlockMaterial = _pinUnlockMaterial();
    final screenshotGateway = _RecordingScreenshotProtectionGateway(
      onUpdate: (_) => Future<void>.error(StateError('shield failed')),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      secureKeyGateway: _RecordingSecureKeyGateway(
        unlockResult: unlockMaterial,
      ),
    );

    unawaited(
      Future<void>(() {
        orchestrator.unlockWithPin(
          pin: '2468',
          expectedLockEpoch: sessionController.state.lockEpoch,
        );
      }),
    );
    await _drainEventQueue();

    expect(screenshotGateway.obscuredUpdates, [false]);
    expect(sessionController.state.isUnlocked, isFalse);
    expect(unlockMaterial.isCleared, isTrue);
  });

  test(
    'pin unlock re-obscures when a newer lock arrives during shield removal',
    () async {
      final sessionController = LockSessionController();
      final shieldBlocker = Completer<void>();
      final screenshotGateway = _RecordingScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          if (!obscured) {
            await shieldBlocker.future;
          }
        },
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: screenshotGateway,
        secureKeyGateway: _RecordingSecureKeyGateway(
          unlockResult: _pinUnlockMaterial(),
        ),
      );
      final expectedLockEpoch = sessionController.state.lockEpoch;

      final unlockFuture = orchestrator.unlockWithPin(
        pin: '2468',
        expectedLockEpoch: expectedLockEpoch,
      );
      await _waitUntil(
        () =>
            screenshotGateway.obscuredUpdates.length == 1 &&
            screenshotGateway.obscuredUpdates.single == false,
      );

      sessionController.lock();
      shieldBlocker.complete();

      expect(await unlockFuture, isFalse);
      expect(screenshotGateway.obscuredUpdates, [false, true]);
      expect(sessionController.state.isUnlocked, isFalse);
    },
  );

  test('native pin failure keeps shield and session locked', () async {
    final sessionController = LockSessionController();
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      unlockError: const NativeSecurityException(
        code: 'PIN_INCORRECT',
        message: null,
        details: null,
      ),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      secureKeyGateway: secureKeyGateway,
    );

    await expectLater(
      orchestrator.unlockWithPin(
        pin: '0000',
        expectedLockEpoch: sessionController.lockEpoch,
      ),
      throwsA(
        isA<NativeSecurityException>().having(
          (error) => error.code,
          'code',
          'PIN_INCORRECT',
        ),
      ),
    );

    expect(secureKeyGateway.lastPin, '0000');
    expect(screenshotGateway.obscuredUpdates, isEmpty);
    expect(sessionController.isUnlocked, isFalse);
  });

  test(
    'pin unlock installs copied session keys and lock clears them',
    () async {
      final sessionKeyStore = DatabaseSessionKeyStore();
      final sessionController = LockSessionController(
        onLock: sessionKeyStore.clear,
      );
      final unlockMaterial = NativeUnlockResult(
        keyId: '123e4567-e89b-42d3-a456-426614174000',
        databaseKey: Uint8List.fromList(List<int>.filled(32, 7)),
        fieldKey: Uint8List.fromList(List<int>.filled(32, 9)),
        unlockMethod: 'pin',
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: _RecordingSecureKeyGateway(
          unlockResult: unlockMaterial,
        ),
        sessionKeyStore: sessionKeyStore,
      );

      expect(
        await orchestrator.unlockWithPin(
          pin: '2468',
          expectedLockEpoch: sessionController.lockEpoch,
        ),
        isTrue,
      );

      final installed = sessionKeyStore.requireCurrent();
      expect(
        installed.withDatabaseKey((key) => Uint8List.fromList(key)),
        everyElement(7),
      );
      expect(
        installed.withFieldKey((key) => Uint8List.fromList(key)),
        everyElement(9),
      );
      expect(unlockMaterial.isCleared, isTrue);

      sessionController.lock();

      expect(installed.isCleared, isTrue);
      expect(sessionKeyStore.hasKeys, isFalse);
    },
  );
}

SecurityOrchestrator _buildOrchestrator({
  required LockSessionController sessionController,
  required ScreenshotProtectionGateway screenshotGateway,
  BiometricGateway? biometricGateway,
  SecureKeyGateway? secureKeyGateway,
  DatabaseSessionKeyStore? sessionKeyStore,
}) {
  return SecurityOrchestrator(
    biometricGateway: biometricGateway ?? _SuccessfulBiometricGateway(),
    screenshotProtectionGateway: screenshotGateway,
    secureKeyGateway: secureKeyGateway ?? _RecordingSecureKeyGateway(),
    sessionController: sessionController,
    pinStateController: PinStateController(),
    logger: const AppLogger(),
    appIsForeground: () => true,
    sessionKeyStore: sessionKeyStore ?? DatabaseSessionKeyStore(),
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

class _UnexpectedBiometricAuthenticationGateway implements BiometricGateway {
  @override
  Future<bool> authenticate() {
    throw StateError('Legacy biometric authentication was invoked.');
  }

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

class _RecordingSecureKeyGateway implements SecureKeyGateway {
  _RecordingSecureKeyGateway({
    this.unlockResult,
    this.unlockError,
    this.systemUnlockResult,
    this.systemUnlockFuture,
  });

  final NativeUnlockResult? unlockResult;
  final NativeSecurityException? unlockError;
  final NativeUnlockResult? systemUnlockResult;
  final Future<NativeUnlockResult>? systemUnlockFuture;
  String? lastPin;
  int systemUnlockCalls = 0;

  @override
  Future<void> ensureRootKey() async {}

  @override
  Future<String> getDatabasePasswordMaterial() async => 'material';

  @override
  Future<NativeSecurityState> getSecurityState() async {
    return _nativeSecurityState(pinConfigured: false);
  }

  @override
  Future<NativeUnlockResult> unlockWithSystemAuth() async {
    systemUnlockCalls += 1;
    final future = systemUnlockFuture;
    if (future != null) {
      return future;
    }
    return systemUnlockResult ??
        NativeUnlockResult(
          keyId: '123e4567-e89b-42d3-a456-426614174000',
          databaseKey: Uint8List(32),
          fieldKey: Uint8List(32),
          unlockMethod: 'system',
        );
  }

  @override
  Future<void> configurePin({required String pin}) async {
    lastPin = pin;
  }

  @override
  Future<NativeUnlockResult> unlockWithPin({required String pin}) async {
    lastPin = pin;
    final error = unlockError;
    if (error != null) {
      throw error;
    }
    return unlockResult ?? _pinUnlockMaterial();
  }

  @override
  Future<void> removePin() async {}
}

NativeUnlockResult _pinUnlockMaterial() {
  return NativeUnlockResult(
    keyId: '123e4567-e89b-42d3-a456-426614174000',
    databaseKey: Uint8List(32),
    fieldKey: Uint8List(32),
    unlockMethod: 'pin',
  );
}

NativeSecurityState _nativeSecurityState({required bool pinConfigured}) {
  return NativeSecurityState(
    status: NativeSecurityStatus.locked,
    keyId: '123e4567-e89b-42d3-a456-426614174000',
    pinConfigured: pinConfigured,
    deviceCredentialAvailable: true,
    strongBiometricAvailable: true,
    securityLevel: KeySecurityLevel.tee,
  );
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
