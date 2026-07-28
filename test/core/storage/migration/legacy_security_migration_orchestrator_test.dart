import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/shared_preferences_legacy_pin_migration_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('runs migration and cleanup in recoverable order', () async {
    final calls = <String>[];
    final bridge = _FakeMigrationBridge(calls);
    final security = _FakeSecurityBridge(calls);
    final runner = _FakeMigrationRunner(calls);
    final validator = _FakePostSwapValidator(calls);
    final pinStore = _FakeLegacyPinStore(calls, pin: '2468');
    final keys = DatabaseSessionKeyStore();
    addTearDown(keys.clear);
    final orchestrator = LegacySecurityMigrationOrchestrator(
      migrationBridge: bridge,
      securityBridge: security,
      migrationRunner: runner,
      postSwapValidator: validator,
      legacyPinStore: pinStore,
      sessionKeyStore: keys,
    );

    await orchestrator.startOrResume();

    expect(calls, <String>[
      'state',
      'readPin',
      'begin',
      'state',
      'checkpoint',
      'backup',
      'pending',
      'copy',
      'rowsCopied',
      'validated',
      'activate',
      'postValidate',
      'postSwap',
      'cleanup',
      'configurePin:2468',
      'clearPin',
      'commit',
      'finish',
    ]);
    expect(runner.legacyPassword, 'legacy-password');
    expect(runner.databasePassword, List.filled(32, 1).map(_hex).join());
    expect(runner.sourcePath, '/fixed/backup.db');
    expect(runner.pendingPath, '/fixed/pending.db');
    expect(keys.hasKeys, isFalse);
    expect(bridge.material.databaseKey, everyElement(0));
    expect(bridge.material.fieldKey, everyElement(0));
    expect(bridge.material.legacyDatabasePassword, everyElement(0));
  });

  test(
    'copy failure aborts without deleting legacy credentials or pin',
    () async {
      final calls = <String>[];
      final bridge = _FakeMigrationBridge(calls);
      final runner = _FakeMigrationRunner(calls)..failure = StateError('copy');
      final keys = DatabaseSessionKeyStore();
      addTearDown(keys.clear);
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: bridge,
        securityBridge: _FakeSecurityBridge(calls),
        migrationRunner: runner,
        postSwapValidator: _FakePostSwapValidator(calls),
        legacyPinStore: _FakeLegacyPinStore(calls, pin: '2468'),
        sessionKeyStore: keys,
      );

      await expectLater(orchestrator.startOrResume(), throwsStateError);

      expect(calls, contains('abort'));
      expect(calls, containsAllInOrder(<String>['copy', 'pending', 'abort']));
      expect(calls.where((call) => call == 'pending'), hasLength(2));
      expect(calls, isNot(contains('commit')));
      expect(calls, isNot(contains('clearPin')));
      expect(calls, isNot(contains('finish')));
      expect(keys.hasKeys, isFalse);
      expect(bridge.material.databaseKey, everyElement(0));
      expect(bridge.material.fieldKey, everyElement(0));
    },
  );

  test(
    'post-swap validation failure restores the legacy database for retry',
    () async {
      final calls = <String>[];
      final bridge = _FakeMigrationBridge(
        calls,
        initialStage: NativeLegacyMigrationStage.newActivated,
      );
      final validator = _FakePostSwapValidator(calls)
        ..failure = StateError('post-swap');
      final keys = DatabaseSessionKeyStore();
      addTearDown(keys.clear);
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: bridge,
        securityBridge: _FakeSecurityBridge(calls),
        migrationRunner: _FakeMigrationRunner(calls),
        postSwapValidator: validator,
        legacyPinStore: _FakeLegacyPinStore(calls, pin: null),
        sessionKeyStore: keys,
      );

      await expectLater(orchestrator.startOrResume(), throwsStateError);

      expect(
        calls,
        containsAllInOrder(<String>['postValidate', 'pending', 'abort']),
      );
      expect(calls, isNot(contains('cleanup')));
      expect(calls, isNot(contains('commit')));
      expect(calls, isNot(contains('finish')));
      expect(keys.hasKeys, isFalse);
    },
  );

  test(
    'cleanup-complete resume finishes credentials without recopying',
    () async {
      final calls = <String>[];
      final bridge = _FakeMigrationBridge(
        calls,
        initialStage: NativeLegacyMigrationStage.cleanupComplete,
      );
      final keys = DatabaseSessionKeyStore();
      addTearDown(keys.clear);
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: bridge,
        securityBridge: _FakeSecurityBridge(calls),
        migrationRunner: _FakeMigrationRunner(calls),
        postSwapValidator: _FakePostSwapValidator(calls),
        legacyPinStore: _FakeLegacyPinStore(calls, pin: null),
        sessionKeyStore: keys,
      );

      await orchestrator.startOrResume();

      expect(calls, <String>[
        'state',
        'readPin',
        'clearPin',
        'commit',
        'finish',
      ]);
    },
  );

  for (final testCase
      in const <
        ({
          NativeLegacyMigrationStage stage,
          bool copies,
          bool activates,
          bool postValidates,
          bool cleansFiles,
        })
      >[
        (
          stage: NativeLegacyMigrationStage.backupReady,
          copies: true,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.pendingCreated,
          copies: true,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.rowsCopied,
          copies: true,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.validated,
          copies: false,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.oldMoved,
          copies: false,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.newActivated,
          copies: false,
          activates: false,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.postSwapValidated,
          copies: false,
          activates: false,
          postValidates: false,
          cleansFiles: true,
        ),
      ]) {
    test('resumes safely from ${testCase.stage.name}', () async {
      final calls = <String>[];
      final bridge = _FakeMigrationBridge(calls, initialStage: testCase.stage);
      final keys = DatabaseSessionKeyStore();
      addTearDown(keys.clear);
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: bridge,
        securityBridge: _FakeSecurityBridge(calls),
        migrationRunner: _FakeMigrationRunner(calls),
        postSwapValidator: _FakePostSwapValidator(calls),
        legacyPinStore: _FakeLegacyPinStore(calls, pin: null),
        sessionKeyStore: keys,
      );

      await orchestrator.startOrResume();

      expect(calls.contains('copy'), testCase.copies);
      expect(calls.contains('activate'), testCase.activates);
      expect(calls.contains('postValidate'), testCase.postValidates);
      expect(calls.contains('cleanup'), testCase.cleansFiles);
      expect(
        calls,
        containsAllInOrder(<String>['readPin', 'clearPin', 'commit', 'finish']),
      );
      expect(keys.hasKeys, isFalse);
    });
  }

  test('legacy pin store accepts an already-cleared state', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final store = SharedPreferencesLegacyPinMigrationStore(
      loadPreferences: SharedPreferences.getInstance,
    );

    expect(
      await store.read(),
      isA<LegacyPinMigrationMaterial>()
          .having((value) => value.enabled, 'enabled', isFalse)
          .having((value) => value.pin, 'pin', isNull),
    );
    await store.clear();
  });

  test(
    'legacy pin store resumes cleanup while plaintext pin remains',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'security.pin_material': '2468',
        'security.pin_migration_cleanup_pending': true,
      });
      final store = SharedPreferencesLegacyPinMigrationStore(
        loadPreferences: SharedPreferences.getInstance,
      );

      final material = await store.read();

      expect(material.enabled, isTrue);
      expect(material.pin, '2468');
      await store.clear();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('security.pin_material'), isFalse);
      expect(
        preferences.containsKey('security.pin_migration_cleanup_pending'),
        isFalse,
      );
    },
  );

  test(
    'legacy pin store resumes cleanup after plaintext pin removal',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'security.pin_migration_cleanup_pending': true,
      });
      final store = SharedPreferencesLegacyPinMigrationStore(
        loadPreferences: SharedPreferences.getInstance,
      );

      final material = await store.read();

      expect(material.enabled, isFalse);
      expect(material.pin, isNull);
      await store.clear();
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey('security.pin_migration_cleanup_pending'),
        isFalse,
      );
    },
  );

  test('legacy pin store rejects inconsistent plaintext state', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'security.pin_enabled': true,
    });
    final store = SharedPreferencesLegacyPinMigrationStore(
      loadPreferences: SharedPreferences.getInstance,
    );

    await expectLater(store.read(), throwsStateError);
  });
}

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
