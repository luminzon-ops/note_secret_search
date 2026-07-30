part of 'legacy_security_migration_orchestrator_test.dart';

class _FakeMigrationBridge implements NativeSecurityMigrationBridge {
  _FakeMigrationBridge(
    this.calls, {
    NativeLegacyMigrationStage initialStage =
        NativeLegacyMigrationStage.detected,
  }) : state = _state(initialStage);

  final List<String> calls;
  NativeLegacyMigrationState state;
  final NativeUnlockResult material = NativeUnlockResult(
    keyId: _keyId,
    databaseKey: Uint8List.fromList(List<int>.filled(32, 1)),
    fieldKey: Uint8List.fromList(List<int>.filled(32, 2)),
    unlockMethod: 'system',
    legacyDatabasePassword: Uint8List.fromList('legacy-password'.codeUnits),
  );

  @override
  Future<NativeUnlockResult> beginLegacyMigration({
    String reason = '升级安全存储',
  }) async {
    calls.add('begin');
    if (state.stage == NativeLegacyMigrationStage.detected) {
      state = _state(NativeLegacyMigrationStage.keyringReady);
    }
    return material;
  }

  @override
  Future<void> abortLegacyMigration() async => calls.add('abort');

  @override
  Future<void> commitLegacyMigration({
    required String keyId,
    required String activeDigest,
  }) async {
    calls.add('commit');
  }

  @override
  Future<NativeLegacyMigrationState> getLegacyMigrationState() async {
    calls.add('state');
    return state;
  }

  @override
  Future<NativeLegacyMigrationState> prepareLegacyMigrationBackup(
    String keyId,
  ) async => _advance('backup', NativeLegacyMigrationStage.backupReady);

  @override
  Future<NativeLegacyMigrationState> prepareLegacyMigrationPending(
    String keyId,
  ) async => _advance('pending', NativeLegacyMigrationStage.pendingCreated);

  @override
  Future<NativeLegacyMigrationState> markLegacyMigrationRowsCopied(
    String keyId,
  ) async => _advance('rowsCopied', NativeLegacyMigrationStage.rowsCopied);

  @override
  Future<NativeLegacyMigrationState> markLegacyMigrationValidated(
    String keyId,
  ) async => _advance('validated', NativeLegacyMigrationStage.validated);

  @override
  Future<NativeLegacyMigrationState> activateLegacyMigration(
    String keyId,
  ) async => _advance('activate', NativeLegacyMigrationStage.newActivated);

  @override
  Future<NativeLegacyMigrationState> markLegacyMigrationPostSwapValidated(
    String keyId,
  ) async => _advance('postSwap', NativeLegacyMigrationStage.postSwapValidated);

  @override
  Future<NativeLegacyMigrationState> cleanupLegacyMigrationFiles(
    String keyId,
  ) async => _advance('cleanup', NativeLegacyMigrationStage.cleanupComplete);

  @override
  Future<void> finishLegacyMigration(String keyId) async {
    calls.add('finish');
  }

  NativeLegacyMigrationState _advance(
    String call,
    NativeLegacyMigrationStage stage,
  ) {
    calls.add(call);
    state = _state(stage);
    return state;
  }
}

class _FakeSecurityBridge implements NativeSecurityBridge {
  _FakeSecurityBridge(this.calls);

  final List<String> calls;

  @override
  Future<void> configurePin({
    required String pin,
    String reason = '配置备用 PIN',
  }) async {
    calls.add('configurePin:$pin');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMigrationRunner implements LegacyDatabaseMigrationRunner {
  _FakeMigrationRunner(this.calls);

  final List<String> calls;
  Object? failure;
  String? sourcePath;
  String? pendingPath;
  String? legacyPassword;
  String? databasePassword;

  @override
  Future<void> prepareSourceForBackup({
    required String sourcePath,
    required String legacyPassword,
  }) async {
    calls.add('checkpoint');
    this.sourcePath = sourcePath;
    this.legacyPassword = legacyPassword;
  }

  @override
  Future<LegacyDatabaseMigrationResult> migrate({
    required String sourcePath,
    required String pendingPath,
    required String legacyPassword,
    required String databasePassword,
    required String keyId,
  }) async {
    calls.add('copy');
    this.sourcePath = sourcePath;
    this.pendingPath = pendingPath;
    this.legacyPassword = legacyPassword;
    this.databasePassword = databasePassword;
    if (failure case final failure?) {
      throw failure;
    }
    return const LegacyDatabaseMigrationResult(
      sourceSchemaVersion: 3,
      targetSchemaVersion: 4,
      quickCheck: 'ok',
      preservedRowCounts: <String, int>{},
    );
  }
}

class _FakePostSwapValidator implements LegacyMigrationPostSwapValidator {
  _FakePostSwapValidator(this.calls);

  final List<String> calls;
  Object? failure;

  @override
  Future<void> validate({
    required String activePath,
    required String databasePassword,
    required String keyId,
  }) async {
    calls.add('postValidate');
    if (failure case final failure?) {
      throw failure;
    }
  }
}

class _FakeLegacyPinStore implements LegacyPinMigrationStore {
  _FakeLegacyPinStore(this.calls, {required this.pin});

  final List<String> calls;
  final String? pin;

  @override
  Future<LegacyPinMigrationMaterial> read() async {
    calls.add('readPin');
    return LegacyPinMigrationMaterial(enabled: pin != null, pin: pin);
  }

  @override
  Future<void> clear() async => calls.add('clearPin');
}

NativeLegacyMigrationState _state(NativeLegacyMigrationStage stage) {
  return NativeLegacyMigrationState(
    stage: stage,
    keyId: stage == NativeLegacyMigrationStage.detected ? null : _keyId,
    sourcePath: '/fixed/backup.db',
    pendingPath: '/fixed/pending.db',
    activePath: '/fixed/active.db',
    sourceDigest: stage.index >= NativeLegacyMigrationStage.backupReady.index
        ? 'a' * 64
        : null,
    pendingDigest: stage.index >= NativeLegacyMigrationStage.validated.index
        ? 'b' * 64
        : null,
    activeDigest:
        stage.index >= NativeLegacyMigrationStage.postSwapValidated.index
        ? 'b' * 64
        : null,
  );
}

String _hex(int value) => value.toRadixString(16).padLeft(2, '0');

const _keyId = '123e4567-e89b-42d3-a456-426614174000';
