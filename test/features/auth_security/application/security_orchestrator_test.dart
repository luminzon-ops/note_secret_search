import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

void main() {
  test(
    'initialize loads security state without provisioning a root key',
    () async {
      final sessionController = LockSessionController();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        securityState: _nativeSecurityState(pinConfigured: true),
      );
      final database = _RecordingAppDatabase();
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: secureKeyGateway,
        database: database,
      );

      await orchestrator.initialize();

      expect(secureKeyGateway.securityStateCalls, 1);
      expect(secureKeyGateway.provisionCalls, 0);
      expect(database.state.status, DatabaseLifecycleStatus.locked);
      expect(sessionController.isUnlocked, isFalse);
      expect(sessionController.state.pinEnabled, isTrue);
    },
  );

  test(
    'initialize leaves legacy migration pending without authenticating',
    () async {
      final sessionController = LockSessionController();
      final migration = _RecordingLegacySecurityMigration();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        securityState: const NativeSecurityState(
          status: NativeSecurityStatus.legacyMigrationRequired,
          keyId: null,
          pinConfigured: false,
          deviceCredentialAvailable: true,
          strongBiometricAvailable: true,
          securityLevel: KeySecurityLevel.unknown,
        ),
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: secureKeyGateway,
        legacySecurityMigration: migration,
      );

      await orchestrator.initialize();

      expect(migration.calls, 0);
      expect(secureKeyGateway.securityStateCalls, 1);
      expect(sessionController.state.pinEnabled, isFalse);
      expect(sessionController.isUnlocked, isFalse);
    },
  );

  test('explicit legacy migration refreshes state and stays locked', () async {
    final sessionController = LockSessionController();
    final migration = _RecordingLegacySecurityMigration();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      securityStates: <NativeSecurityState>[
        const NativeSecurityState(
          status: NativeSecurityStatus.legacyMigrationRequired,
          keyId: null,
          pinConfigured: false,
          deviceCredentialAvailable: true,
          strongBiometricAvailable: true,
          securityLevel: KeySecurityLevel.unknown,
        ),
        _nativeSecurityState(pinConfigured: true),
      ],
    );
    final database = _RecordingAppDatabase();
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: _RecordingScreenshotProtectionGateway(),
      secureKeyGateway: secureKeyGateway,
      database: database,
      legacySecurityMigration: migration,
    );

    await orchestrator.initialize();
    final refreshed = await orchestrator.migrateLegacySecurity();

    expect(refreshed.status, NativeSecurityStatus.locked);
    expect(migration.calls, 1);
    expect(secureKeyGateway.securityStateCalls, 2);
    expect(sessionController.state.pinEnabled, isTrue);
    expect(sessionController.isUnlocked, isFalse);
    expect(database.state.status, DatabaseLifecycleStatus.locked);
  });

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

  test(
    'pin recovery rebinds system authentication before opening data',
    () async {
      final sessionController = LockSessionController();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        securityState: _nativeSecurityState(
          pinConfigured: true,
          systemRebindRequired: true,
        ),
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        secureKeyGateway: secureKeyGateway,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
      );

      final unlocked = await orchestrator.unlockWithPin(
        pin: '2468',
        expectedLockEpoch: 0,
      );

      expect(unlocked, isTrue);
      expect(secureKeyGateway.rebindCalls, 1);
      expect(secureKeyGateway.lastPin, '2468');
    },
  );

  test('cancelled system rebind does not revoke a valid pin unlock', () async {
    final sessionController = LockSessionController();
    final secureKeyGateway = _RecordingSecureKeyGateway(
      securityState: _nativeSecurityState(
        pinConfigured: true,
        systemRebindRequired: true,
      ),
      rebindError: const NativeSecurityException(
        code: 'AUTH_CANCELLED',
        message: null,
        details: null,
      ),
    );
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      secureKeyGateway: secureKeyGateway,
      screenshotGateway: _RecordingScreenshotProtectionGateway(),
    );

    final unlocked = await orchestrator.unlockWithPin(
      pin: '2468',
      expectedLockEpoch: 0,
    );

    expect(unlocked, isTrue);
    expect(secureKeyGateway.rebindCalls, 1);
  });

  test(
    'system provisioning opens the database and unlocks the session',
    () async {
      final sessionController = LockSessionController();
      final provisionMaterial = NativeUnlockResult(
        keyId: '123e4567-e89b-42d3-a456-426614174000',
        databaseKey: Uint8List.fromList(List<int>.filled(32, 0x31)),
        fieldKey: Uint8List.fromList(List<int>.filled(32, 0x42)),
        unlockMethod: 'system',
      );
      final secureKeyGateway = _RecordingSecureKeyGateway(
        provisionResult: provisionMaterial,
      );
      final database = _RecordingAppDatabase();
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: secureKeyGateway,
        database: database,
      );

      expect(await orchestrator.provisionWithSystemAuth(), isTrue);

      expect(secureKeyGateway.provisionCalls, 1);
      expect(secureKeyGateway.systemUnlockCalls, 0);
      expect(database.state.status, DatabaseLifecycleStatus.open);
      expect(sessionController.isUnlocked, isTrue);
      expect(provisionMaterial.isCleared, isTrue);
    },
  );

  test('unlock waits for the database before removing the shield', () async {
    final sessionController = LockSessionController();
    final openStarted = Completer<void>();
    final releaseOpen = Completer<void>();
    final database = _RecordingAppDatabase(
      onOpen: (_) async {
        openStarted.complete();
        await releaseOpen.future;
      },
    );
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      database: database,
    );

    final unlocking = orchestrator.unlockWithBiometrics();
    await openStarted.future;

    expect(database.state.status, DatabaseLifecycleStatus.opening);
    expect(sessionController.isUnlocked, isFalse);
    expect(screenshotGateway.obscuredUpdates, isEmpty);

    releaseOpen.complete();
    expect(await unlocking, isTrue);
    expect(database.state.status, DatabaseLifecycleStatus.open);
    expect(screenshotGateway.obscuredUpdates, [false]);
    expect(sessionController.isUnlocked, isTrue);
  });

  test(
    'a concurrent unlock is rejected before requesting new key material',
    () async {
      final sessionController = LockSessionController();
      final firstMaterial = NativeUnlockResult(
        keyId: '123e4567-e89b-42d3-a456-426614174000',
        databaseKey: Uint8List.fromList(List<int>.filled(32, 0x17)),
        fieldKey: Uint8List.fromList(List<int>.filled(32, 0x29)),
        unlockMethod: 'system',
      );
      final authenticationBlocker = Completer<NativeUnlockResult>();
      final secureKeyGateway = _RecordingSecureKeyGateway(
        systemUnlockFuture: authenticationBlocker.future,
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        secureKeyGateway: secureKeyGateway,
      );

      final firstUnlock = orchestrator.unlockWithBiometrics();
      await _waitUntil(() => secureKeyGateway.systemUnlockCalls == 1);

      final concurrentUnlock = await orchestrator.unlockWithPin(
        pin: '2468',
        expectedLockEpoch: sessionController.lockEpoch,
      );
      authenticationBlocker.complete(firstMaterial);
      final firstResult = await firstUnlock;

      expect(concurrentUnlock, isFalse);
      expect(secureKeyGateway.pinUnlockCalls, 0);
      expect(firstResult, isTrue);
      expect(sessionController.isUnlocked, isTrue);
      expect(firstMaterial.isCleared, isTrue);
    },
  );

  test(
    'database open failure stays sanitized and clears unlock keys',
    () async {
      final sessionController = LockSessionController();
      final sessionKeyStore = DatabaseSessionKeyStore();
      final database = _RecordingAppDatabase(
        onOpen: (_) async {
          throw const DatabaseLifecycleException('database_open_failed');
        },
      );
      final orchestrator = _buildOrchestrator(
        sessionController: sessionController,
        screenshotGateway: _RecordingScreenshotProtectionGateway(),
        sessionKeyStore: sessionKeyStore,
        database: database,
      );

      await expectLater(
        orchestrator.unlockWithBiometrics(),
        throwsA(
          isA<DatabaseLifecycleException>().having(
            (error) => error.code,
            'code',
            'database_open_failed',
          ),
        ),
      );

      expect(sessionController.isUnlocked, isFalse);
      expect(sessionKeyStore.hasKeys, isFalse);
      expect(database.state.status, DatabaseLifecycleStatus.locked);
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

  test('lock revokes database access before clearing session keys', () async {
    final sessionController = LockSessionController();
    final sessionKeyStore = DatabaseSessionKeyStore();
    final closeStarted = Completer<void>();
    final releaseClose = Completer<void>();
    final database = _RecordingAppDatabase(
      onClose: () async {
        expect(sessionController.isUnlocked, isTrue);
        closeStarted.complete();
        await releaseClose.future;
      },
    );
    final screenshotGateway = _RecordingScreenshotProtectionGateway();
    final orchestrator = _buildOrchestrator(
      sessionController: sessionController,
      screenshotGateway: screenshotGateway,
      sessionKeyStore: sessionKeyStore,
      database: database,
    );
    expect(await orchestrator.unlockWithBiometrics(), isTrue);
    screenshotGateway.obscuredUpdates.clear();

    final locking = orchestrator.lock();
    await closeStarted.future;

    expect(screenshotGateway.obscuredUpdates, [true]);
    expect(database.state.status, DatabaseLifecycleStatus.closing);
    expect(sessionController.isUnlocked, isFalse);
    expect(sessionKeyStore.hasKeys, isTrue);

    releaseClose.complete();
    await locking;

    expect(database.state.status, DatabaseLifecycleStatus.locked);
    expect(sessionKeyStore.hasKeys, isFalse);
  });
}

SecurityOrchestrator _buildOrchestrator({
  required LockSessionController sessionController,
  required ScreenshotProtectionGateway screenshotGateway,
  BiometricGateway? biometricGateway,
  SecureKeyGateway? secureKeyGateway,
  DatabaseSessionKeyStore? sessionKeyStore,
  AppDatabase? database,
  LegacySecurityMigrationRunner? legacySecurityMigration,
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
    database: database ?? _RecordingAppDatabase(),
    legacySecurityMigration: legacySecurityMigration,
  );
}

class _RecordingAppDatabase implements AppDatabase {
  _RecordingAppDatabase({this.onOpen, this.onClose});

  final Future<void> Function(DatabaseSessionKeys keys)? onOpen;
  final Future<void> Function()? onClose;
  DatabaseLifecycleState _state = const DatabaseLifecycleState.locked();

  @override
  DatabaseLifecycleState get state => _state;

  @override
  Stream<DatabaseLifecycleState> get states => const Stream.empty();

  @override
  Future<void> open(DatabaseSessionKeys sessionKeys) async {
    _state = const DatabaseLifecycleState(
      status: DatabaseLifecycleStatus.opening,
    );
    await onOpen?.call(sessionKeys);
    _state = const DatabaseLifecycleState(status: DatabaseLifecycleStatus.open);
  }

  @override
  Future<T> run<T>(Future<T> Function(Database database) operation) {
    throw UnimplementedError();
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(DatabaseExecutor executor) operation,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {
    _state = const DatabaseLifecycleState(
      status: DatabaseLifecycleStatus.closing,
    );
    await onClose?.call();
    _state = const DatabaseLifecycleState.locked();
  }
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
    this.securityState,
    this.securityStates,
    this.provisionResult,
    this.rebindError,
  });

  final NativeUnlockResult? unlockResult;
  final NativeSecurityException? unlockError;
  final NativeUnlockResult? systemUnlockResult;
  final Future<NativeUnlockResult>? systemUnlockFuture;
  final NativeSecurityState? securityState;
  final List<NativeSecurityState>? securityStates;
  final NativeUnlockResult? provisionResult;
  final NativeSecurityException? rebindError;
  String? lastPin;
  int systemUnlockCalls = 0;
  int securityStateCalls = 0;
  int provisionCalls = 0;
  int pinUnlockCalls = 0;
  int rebindCalls = 0;

  @override
  Future<NativeSecurityState> getSecurityState() async {
    securityStateCalls += 1;
    final states = securityStates;
    if (states != null && states.isNotEmpty) {
      return states.removeAt(0);
    }
    return securityState ?? _nativeSecurityState(pinConfigured: false);
  }

  @override
  Future<NativeUnlockResult> provisionWithSystemAuth() async {
    provisionCalls += 1;
    return provisionResult ??
        NativeUnlockResult(
          keyId: '123e4567-e89b-42d3-a456-426614174000',
          databaseKey: Uint8List(32),
          fieldKey: Uint8List(32),
          unlockMethod: 'system',
        );
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
    pinUnlockCalls += 1;
    lastPin = pin;
    final error = unlockError;
    if (error != null) {
      throw error;
    }
    return unlockResult ?? _pinUnlockMaterial();
  }

  @override
  Future<void> rebindSystemAuthWithPin({required String pin}) async {
    rebindCalls += 1;
    lastPin = pin;
    final error = rebindError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> removePin() async {}
}

class _RecordingLegacySecurityMigration
    implements LegacySecurityMigrationRunner {
  int calls = 0;

  @override
  Future<void> startOrResume() async {
    calls += 1;
  }
}

NativeUnlockResult _pinUnlockMaterial() {
  return NativeUnlockResult(
    keyId: '123e4567-e89b-42d3-a456-426614174000',
    databaseKey: Uint8List(32),
    fieldKey: Uint8List(32),
    unlockMethod: 'pin',
  );
}

NativeSecurityState _nativeSecurityState({
  required bool pinConfigured,
  bool systemRebindRequired = false,
}) {
  return NativeSecurityState(
    status: NativeSecurityStatus.locked,
    keyId: '123e4567-e89b-42d3-a456-426614174000',
    pinConfigured: pinConfigured,
    deviceCredentialAvailable: true,
    strongBiometricAvailable: true,
    securityLevel: KeySecurityLevel.tee,
    systemRebindRequired: systemRebindRequired,
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
