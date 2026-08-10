import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/legacy_database_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('source open failure preserves existing pending data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'legacy_migration_source_failure_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final pending = File(
      '${directory.path}${Platform.pathSeparator}pending.db',
    );
    final sentinel = Uint8List.fromList(const <int>[1, 3, 3, 7]);
    await pending.writeAsBytes(sentinel, flush: true);
    final harness = _FailureHarness(
      databaseFactory: const _FailingLegacyDatabaseFactory(),
    );
    addTearDown(harness.dispose);

    await expectLater(
      harness.migrator.migrate(
        sourcePath: '${directory.path}${Platform.pathSeparator}source.db',
        pendingPath: pending.path,
        legacyPassword: 'wrong-password',
        databasePassword: 'new-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsA(
        isA<LegacyDatabaseMigrationException>().having(
          (error) => error.failure,
          'failure',
          LegacyDatabaseMigrationFailure.sourceUnavailable,
        ),
      ),
    );

    expect(await pending.readAsBytes(), orderedEquals(sentinel));
  });

  test(
    'pending open failure leaves cleanup to the native coordinator',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.v1,
      );
      addTearDown(fixture.dispose);
      final harness = _FailureHarness(
        databaseFactory: const _FailingPendingDatabaseFactory(),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.migrator.migrate(
          sourcePath: fixture.sourcePath,
          pendingPath: fixture.pendingPath,
          legacyPassword: 'legacy-password',
          databasePassword: 'new-password',
          keyId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.failure,
            'failure',
            LegacyDatabaseMigrationFailure.pendingUnavailable,
          ),
        ),
      );

      expect(
        await File(fixture.pendingPath).readAsBytes(),
        orderedEquals(const <int>[4, 2]),
      );
    },
  );

  test(
    'missing required source table aborts before touching pending data',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.v2,
      );
      addTearDown(fixture.dispose);
      final source = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
      await source.execute('DROP TABLE secret_items');
      await source.close();
      final pending = File(fixture.pendingPath);
      final sentinel = Uint8List.fromList(const <int>[8, 6, 7, 5, 3, 0, 9]);
      await pending.writeAsBytes(sentinel, flush: true);
      final harness = _FailureHarness(
        databaseFactory: const _FfiMigrationDatabaseFactory(),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.migrator.migrate(
          sourcePath: fixture.sourcePath,
          pendingPath: fixture.pendingPath,
          legacyPassword: 'legacy-password',
          databasePassword: 'new-password',
          keyId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.failure.name,
            'failure',
            'sourceSchemaMismatch',
          ),
        ),
      );

      expect(await pending.readAsBytes(), orderedEquals(sentinel));
    },
  );

  for (final version in legacyMigrationSourceVersions) {
    test(
      '${version.name} missing password column aborts before touching pending',
      () async {
        final fixture = await createLegacyDatabaseFixture(version);
        addTearDown(fixture.dispose);
        final source = await databaseFactoryFfi.openDatabase(
          fixture.sourcePath,
        );
        await source.execute(
          'ALTER TABLE secret_items DROP COLUMN password_ciphertext',
        );
        await source.close();
        final pending = File(fixture.pendingPath);
        final sentinel = Uint8List.fromList(const <int>[4, 8, 15, 16, 23, 42]);
        await pending.writeAsBytes(sentinel, flush: true);
        final harness = _FailureHarness(
          databaseFactory: const _FfiMigrationDatabaseFactory(),
        );
        addTearDown(harness.dispose);

        await expectLater(
          harness.migrator.migrate(
            sourcePath: fixture.sourcePath,
            pendingPath: fixture.pendingPath,
            legacyPassword: 'legacy-password',
            databasePassword: 'new-password',
            keyId: '123e4567-e89b-42d3-a456-426614174000',
          ),
          throwsA(
            isA<LegacyDatabaseMigrationException>().having(
              (error) => error.failure,
              'failure',
              LegacyDatabaseMigrationFailure.sourceSchemaMismatch,
            ),
          ),
        );

        expect(await pending.readAsBytes(), orderedEquals(sentinel));
      },
    );
  }

  test('missing source primary key constraint aborts migration', () async {
    final fixture = await createLegacyDatabaseFixture(LegacyFixtureVersion.v2);
    addTearDown(fixture.dispose);
    final source = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
    await source.execute('ALTER TABLE secret_items RENAME TO old_secret_items');
    await source.execute(
      'CREATE TABLE secret_items AS SELECT * FROM old_secret_items',
    );
    await source.execute('DROP TABLE old_secret_items');
    await source.close();
    final harness = _FailureHarness(
      databaseFactory: const _FfiMigrationDatabaseFactory(),
    );
    addTearDown(harness.dispose);

    await expectLater(
      harness.migrator.migrate(
        sourcePath: fixture.sourcePath,
        pendingPath: fixture.pendingPath,
        legacyPassword: 'legacy-password',
        databasePassword: 'new-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsA(
        isA<LegacyDatabaseMigrationException>().having(
          (error) => error.failure,
          'failure',
          LegacyDatabaseMigrationFailure.sourceSchemaMismatch,
        ),
      ),
    );
  });

  test(
    'corrupt provider JSON leaves pending cleanup to native ownership',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.v2,
      );
      addTearDown(fixture.dispose);
      final source = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
      await source.update(
        'provider_configs',
        <String, Object?>{
          'encrypted_config': Uint8List.fromList(utf8.encode('{"apiKey":')),
        },
        where: 'id = ?',
        whereArgs: const <Object>['provider-1'],
      );
      await source.close();
      final harness = _FailureHarness(
        databaseFactory: const _FfiMigrationDatabaseFactory(),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.migrator.migrate(
          sourcePath: fixture.sourcePath,
          pendingPath: fixture.pendingPath,
          legacyPassword: 'legacy-password',
          databasePassword: 'new-password',
          keyId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsFormatException,
      );

      expect(File(fixture.pendingPath).existsSync(), isTrue);
    },
  );

  test('repeated execution succeeds after the native pending reset', () async {
    final fixture = await createLegacyDatabaseFixture(
      LegacyFixtureVersion.freshV3,
    );
    addTearDown(fixture.dispose);
    final harness = _FailureHarness(
      databaseFactory: const _FfiMigrationDatabaseFactory(),
    );
    addTearDown(harness.dispose);
    await File(
      fixture.pendingPath,
    ).writeAsBytes(const <int>[0, 1, 2], flush: true);

    for (var attempt = 0; attempt < 2; attempt += 1) {
      await _deleteSqliteFileSet(fixture.pendingPath);
      final result = await harness.migrator.migrate(
        sourcePath: fixture.sourcePath,
        pendingPath: fixture.pendingPath,
        legacyPassword: 'legacy-password',
        databasePassword: 'new-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      );
      expect(result.quickCheck, 'ok');
    }

    final pending = await databaseFactoryFfi.openDatabase(fixture.pendingPath);
    addTearDown(pending.close);
    expect(await pending.query('security_metadata'), hasLength(1));
    expect(await pending.query('secret_items'), hasLength(2));
    expect(await pending.query('chat_messages'), hasLength(1));
  });
}

Future<void> _deleteSqliteFileSet(String path) async {
  for (final candidate in <String>[path, '$path-wal', '$path-shm']) {
    final file = File(candidate);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}

class _FailureHarness {
  _FailureHarness({required MigrationDatabaseFactory databaseFactory})
    : keys = DatabaseSessionKeys(
        databaseKey: Uint8List(32),
        fieldKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      ) {
    keyStore.replace(keys);
    migrator = LegacyDatabaseMigrator(
      databaseFactory: databaseFactory,
      cryptoService: AesGcmFieldCrypto(sessionKeyStore: keyStore),
    );
  }

  final DatabaseSessionKeyStore keyStore = DatabaseSessionKeyStore();
  final DatabaseSessionKeys keys;
  late final LegacyDatabaseMigrator migrator;

  void dispose() => keyStore.clear();
}

class _FailingLegacyDatabaseFactory implements MigrationDatabaseFactory {
  const _FailingLegacyDatabaseFactory();

  @override
  Future<Database> openLegacyForCheckpoint({
    required String path,
    required String password,
  }) {
    throw StateError('test source checkpoint failure');
  }

  @override
  Future<Database> openLegacy({
    required String path,
    required String password,
  }) {
    throw StateError('test source open failure');
  }

  @override
  Future<Database> openPending({
    required String path,
    required String password,
    required int version,
    required OnDatabaseCreateFn onCreate,
  }) {
    throw StateError('pending must remain unopened');
  }
}

class _FailingPendingDatabaseFactory implements MigrationDatabaseFactory {
  const _FailingPendingDatabaseFactory();

  @override
  Future<Database> openLegacyForCheckpoint({
    required String path,
    required String password,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: false, singleInstance: false),
    );
  }

  @override
  Future<Database> openLegacy({
    required String path,
    required String password,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
  }

  @override
  Future<Database> openPending({
    required String path,
    required String password,
    required int version,
    required OnDatabaseCreateFn onCreate,
  }) async {
    await File(path).writeAsBytes(const <int>[4, 2], flush: true);
    throw StateError('test pending open failure');
  }
}

class _FfiMigrationDatabaseFactory implements MigrationDatabaseFactory {
  const _FfiMigrationDatabaseFactory();

  @override
  Future<Database> openLegacyForCheckpoint({
    required String path,
    required String password,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: false, singleInstance: false),
    );
  }

  @override
  Future<Database> openLegacy({
    required String path,
    required String password,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
  }

  @override
  Future<Database> openPending({
    required String path,
    required String password,
    required int version,
    required OnDatabaseCreateFn onCreate,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: onCreate,
        singleInstance: false,
      ),
    );
  }
}
