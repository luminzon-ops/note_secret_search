import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/shared_preferences_legacy_pin_migration_store.dart';

void main() {
  test(
    'inconsistent legacy pin fails before cleanup and credential commit',
    () async {
      final calls = <String>[];
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: _PostSwapMigrationBridge(calls),
        securityBridge: _UnusedSecurityBridge(),
        migrationRunner: _UnusedMigrationRunner(),
        postSwapValidator: _UnusedPostSwapValidator(),
        legacyPinStore: _ThrowingLegacyPinStore(calls),
        sessionKeyStore: DatabaseSessionKeyStore(),
      );

      await expectLater(orchestrator.startOrResume(), throwsStateError);

      expect(calls, <String>['state', 'readPin']);
      expect(calls, isNot(contains('begin')));
      expect(calls, isNot(contains('cleanup')));
      expect(calls, isNot(contains('commit')));
    },
  );

  test('partial plaintext pin cleanup keeps its retry marker', () async {
    final preferences = _FailingLegacyPinPreferences(<String, Object>{
      'security.pin_enabled': true,
      'security.pin_material': '2468',
    }, failRemoveKey: 'security.pin_material');
    final store = SharedPreferencesLegacyPinMigrationStore.withPreferenceStore(
      preferences,
    );

    await expectLater(store.clear(), throwsStateError);

    expect(preferences.values['security.pin_enabled'], isNull);
    expect(preferences.values['security.pin_material'], '2468');
    expect(
      preferences.values['security.pin_migration_cleanup_pending'],
      isTrue,
    );

    preferences.failRemoveKey = null;
    final resumed = await store.read();
    expect(resumed.enabled, isTrue);
    expect(resumed.pin, '2468');
    await store.clear();
    expect(preferences.values, isEmpty);
  });
}

class _PostSwapMigrationBridge implements NativeSecurityMigrationBridge {
  _PostSwapMigrationBridge(this.calls);

  final List<String> calls;

  @override
  Future<NativeUnlockResult> beginLegacyMigration({
    String reason = '升级安全存储',
  }) async {
    calls.add('begin');
    return NativeUnlockResult(
      keyId: _keyId,
      databaseKey: Uint8List(32),
      fieldKey: Uint8List(32),
      unlockMethod: 'system',
      legacyDatabasePassword: Uint8List.fromList('legacy-password'.codeUnits),
    );
  }

  @override
  Future<void> abortLegacyMigration() async => calls.add('abort');

  @override
  Future<NativeLegacyMigrationState> cleanupLegacyMigrationFiles(
    String keyId,
  ) async {
    calls.add('cleanup');
    return _state(NativeLegacyMigrationStage.cleanupComplete);
  }

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
    return _state(NativeLegacyMigrationStage.postSwapValidated);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingLegacyPinStore implements LegacyPinMigrationStore {
  _ThrowingLegacyPinStore(this.calls);

  final List<String> calls;

  @override
  Future<void> clear() async => calls.add('clearPin');

  @override
  Future<LegacyPinMigrationMaterial> read() async {
    calls.add('readPin');
    throw StateError('legacy_pin_state_inconsistent');
  }
}

class _UnusedSecurityBridge implements NativeSecurityBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedMigrationRunner implements LegacyDatabaseMigrationRunner {
  @override
  Future<LegacyDatabaseMigrationResult> migrate({
    required String sourcePath,
    required String pendingPath,
    required String legacyPassword,
    required String databasePassword,
    required String keyId,
  }) {
    throw StateError('migration runner must not be called');
  }

  @override
  Future<void> prepareSourceForBackup({
    required String sourcePath,
    required String legacyPassword,
  }) {
    throw StateError('migration runner must not be called');
  }
}

class _UnusedPostSwapValidator implements LegacyMigrationPostSwapValidator {
  @override
  Future<void> validate({
    required String activePath,
    required String databasePassword,
    required String keyId,
  }) {
    throw StateError('post-swap validator must not be called');
  }
}

class _FailingLegacyPinPreferences implements LegacyPinPreferenceStore {
  _FailingLegacyPinPreferences(this.values, {this.failRemoveKey});

  final Map<String, Object> values;
  String? failRemoveKey;

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> remove(String key) async {
    if (key == failRemoveKey) {
      return false;
    }
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    return true;
  }
}

NativeLegacyMigrationState _state(NativeLegacyMigrationStage stage) {
  return NativeLegacyMigrationState(
    stage: stage,
    keyId: _keyId,
    sourcePath: '/fixed/backup.db',
    pendingPath: '/fixed/pending.db',
    activePath: '/fixed/active.db',
    sourceDigest: 'a' * 64,
    pendingDigest: 'b' * 64,
    activeDigest: 'b' * 64,
  );
}

const _keyId = '123e4567-e89b-42d3-a456-426614174000';
