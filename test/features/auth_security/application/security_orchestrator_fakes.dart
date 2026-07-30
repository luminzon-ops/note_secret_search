part of 'security_orchestrator_test.dart';

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
