import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/legacy_database_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'migrates a v1 database into a validated schema-v4 pending file',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.v1,
      );
      addTearDown(fixture.dispose);
      final keys = DatabaseSessionKeys(
        databaseKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
        fieldKey: Uint8List.fromList(List<int>.generate(32, (i) => 0x80 + i)),
      );
      addTearDown(keys.clear);
      final keyStore = DatabaseSessionKeyStore()..replace(keys);
      final crypto = AesGcmFieldCrypto(sessionKeyStore: keyStore);
      final migrator = LegacyDatabaseMigrator(
        databaseFactory: const _FfiMigrationDatabaseFactory(),
        cryptoService: crypto,
        now: () => DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000),
      );

      final result = await migrator.migrate(
        sourcePath: fixture.sourcePath,
        pendingPath: fixture.pendingPath,
        legacyPassword: 'legacy-password',
        databasePassword: 'new-database-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      );

      expect(result.sourceSchemaVersion, 1);
      expect(result.targetSchemaVersion, 4);
      expect(result.quickCheck, 'ok');
      expect(result.preservedRowCounts, containsPair('secret_items', 2));
      expect(result.preservedRowCounts, containsPair('note_items', 2));
      expect(result.preservedRowCounts, containsPair('model_registry', 1));
      expect(result.preservedRowCounts, containsPair('chat_sessions', 0));

      final target = await databaseFactoryFfi.openDatabase(fixture.pendingPath);
      addTearDown(target.close);
      expect(
        (await target.rawQuery('PRAGMA user_version')).single['user_version'],
        4,
      );
      expect(await _count(target, 'embedding_chunks'), 0);
      expect(await _count(target, 'download_tasks'), 0);
      expect(await _count(target, 'model_catalog_entries'), 0);
      expect(await _count(target, 'secret_items'), 2);
      expect(await _count(target, 'note_items'), 2);

      final metadata = (await target.query('security_metadata')).single;
      expect(metadata['key_id'], '123e4567-e89b-42d3-a456-426614174000');
      expect(metadata['source_schema_version'], 1);
      expect(metadata['field_envelope_version'], 1);
      expect(metadata['migration_state'], 'validated');

      await _expectEncryptedFields(target, crypto, fixture.expectedPlaintext);

      final deletedSecret = (await target.query(
        'secret_items',
        where: 'id = ?',
        whereArgs: const <Object>['secret-deleted'],
      )).single;
      expect(deletedSecret['deleted_at'], isNotNull);
      final deletedNote = (await target.query(
        'note_items',
        where: 'id = ?',
        whereArgs: const <Object>['note-deleted'],
      )).single;
      expect(deletedNote['deleted_at'], isNotNull);

      final model = (await target.query('model_registry')).single;
      expect(model['integrity_status'], 'unknown');
      expect(model['artifact_paths_json'], isNull);

      final providerPlaintext = crypto.decryptField(
        (await target.query('provider_configs')).single['encrypted_config']
            as List<int>,
        field: EncryptedDatabaseField.providerConfig,
        rowId: 'provider-1',
      );
      expect(jsonDecode(providerPlaintext), isA<Map<String, Object?>>());
    },
  );

  for (final testCase
      in const <
        ({
          LegacyFixtureVersion version,
          String name,
          int schemaVersion,
          String? artifactPaths,
          String integrityStatus,
        })
      >[
        (
          version: LegacyFixtureVersion.v2,
          name: 'v2',
          schemaVersion: 2,
          artifactPaths: null,
          integrityStatus: 'unknown',
        ),
        (
          version: LegacyFixtureVersion.upgradedV3,
          name: 'an upgraded v3',
          schemaVersion: 3,
          artifactPaths: '["/models/legacy.onnx"]',
          integrityStatus: 'unknown',
        ),
        (
          version: LegacyFixtureVersion.freshV3,
          name: 'a fresh v3',
          schemaVersion: 3,
          artifactPaths: '["/models/legacy.onnx"]',
          integrityStatus: 'verified',
        ),
      ]) {
    test(
      'migrates ${testCase.name} database without losing compatible rows',
      () async {
        final fixture = await createLegacyDatabaseFixture(testCase.version);
        addTearDown(fixture.dispose);
        final harness = _MigrationHarness();
        addTearDown(harness.dispose);

        final result = await harness.migrator.migrate(
          sourcePath: fixture.sourcePath,
          pendingPath: fixture.pendingPath,
          legacyPassword: 'legacy-password',
          databasePassword: 'new-database-password',
          keyId: '123e4567-e89b-42d3-a456-426614174000',
        );

        expect(result.sourceSchemaVersion, testCase.schemaVersion);
        expect(result.preservedRowCounts['chat_sessions'], 1);
        expect(result.preservedRowCounts['chat_messages'], 1);

        final target = await databaseFactoryFfi.openDatabase(
          fixture.pendingPath,
        );
        addTearDown(target.close);
        expect(await _count(target, 'chat_sessions'), 1);
        expect(await _count(target, 'chat_messages'), 1);
        expect(await _count(target, 'embedding_chunks'), 0);
        final model = (await target.query('model_registry')).single;
        expect(model['artifact_paths_json'], testCase.artifactPaths);
        expect(model['integrity_status'], testCase.integrityStatus);
        await _expectEncryptedFields(
          target,
          harness.crypto,
          fixture.expectedPlaintext,
        );
      },
    );
  }

  test('rejects invalid legacy UTF-8 and removes the pending file', () async {
    final fixture = await createLegacyDatabaseFixture(LegacyFixtureVersion.v1);
    addTearDown(fixture.dispose);
    final source = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
    await source.update(
      'secret_items',
      <String, Object?>{
        'password_ciphertext': Uint8List.fromList(const <int>[0xff]),
      },
      where: 'id = ?',
      whereArgs: const <Object>['secret-1'],
    );
    await source.close();
    final harness = _MigrationHarness();
    addTearDown(harness.dispose);

    await expectLater(
      harness.migrator.migrate(
        sourcePath: fixture.sourcePath,
        pendingPath: fixture.pendingPath,
        legacyPassword: 'legacy-password',
        databasePassword: 'new-database-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsFormatException,
    );

    expect(File(fixture.pendingPath).existsSync(), isFalse);
  });

  test('rejects a pending database that changes migrated plaintext', () async {
    final fixture = await createLegacyDatabaseFixture(LegacyFixtureVersion.v1);
    addTearDown(fixture.dispose);
    final harness = _MigrationHarness(corruptNoteContent: true);
    addTearDown(harness.dispose);

    await expectLater(
      harness.migrator.migrate(
        sourcePath: fixture.sourcePath,
        pendingPath: fixture.pendingPath,
        legacyPassword: 'legacy-password',
        databasePassword: 'new-database-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsStateError,
    );

    expect(File(fixture.pendingPath).existsSync(), isFalse);
  });

  test(
    'rejects a non-legacy source before touching existing pending data',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.v1,
      );
      addTearDown(fixture.dispose);
      final source = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
      await source.execute('PRAGMA user_version = 4');
      await source.close();
      final pending = File(fixture.pendingPath);
      final sentinel = Uint8List.fromList(const <int>[9, 8, 7, 6]);
      await pending.writeAsBytes(sentinel, flush: true);
      final harness = _MigrationHarness();
      addTearDown(harness.dispose);

      await expectLater(
        harness.migrator.migrate(
          sourcePath: fixture.sourcePath,
          pendingPath: fixture.pendingPath,
          legacyPassword: 'legacy-password',
          databasePassword: 'new-database-password',
          keyId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.failure,
            'failure',
            LegacyDatabaseMigrationFailure.unsupportedSourceVersion,
          ),
        ),
      );

      expect(await pending.readAsBytes(), orderedEquals(sentinel));
    },
  );
}

Future<int> _count(Database database, String table) async {
  final row = (await database.rawQuery(
    'SELECT COUNT(*) AS count FROM $table',
  )).single;
  return row['count']! as int;
}

Future<void> _expectEncryptedFields(
  Database database,
  AesGcmFieldCrypto crypto,
  Map<String, String?> expected,
) async {
  final secretRows = await database.query('secret_items');
  for (final row in secretRows) {
    final id = row['id']! as String;
    for (final field in const <EncryptedDatabaseField>[
      EncryptedDatabaseField.secretUsername,
      EncryptedDatabaseField.secretPassword,
      EncryptedDatabaseField.secretWebsiteUrl,
      EncryptedDatabaseField.secretNote,
    ]) {
      final expectedValue = expected['$id.${field.column}'];
      final ciphertext = row[field.column] as List<int>?;
      if (expectedValue == null) {
        expect(ciphertext, isNull);
      } else {
        expect(ciphertext, isNot(equals(utf8.encode(expectedValue))));
        expect(
          crypto.decryptField(ciphertext, field: field, rowId: id),
          expectedValue,
        );
      }
    }
  }

  final noteRows = await database.query('note_items');
  for (final row in noteRows) {
    final id = row['id']! as String;
    for (final field in const <EncryptedDatabaseField>[
      EncryptedDatabaseField.noteContent,
      EncryptedDatabaseField.noteSummary,
    ]) {
      final expectedValue = expected['$id.${field.column}'];
      final ciphertext = row[field.column] as List<int>?;
      if (expectedValue == null) {
        expect(ciphertext, isNull);
      } else {
        expect(
          crypto.decryptField(ciphertext, field: field, rowId: id),
          expectedValue,
        );
      }
    }
  }

  final protectedRows =
      <({String table, String idColumn, EncryptedDatabaseField field})>[
        (
          table: 'provider_configs',
          idColumn: 'id',
          field: EncryptedDatabaseField.providerConfig,
        ),
        (
          table: 'sync_accounts',
          idColumn: 'id',
          field: EncryptedDatabaseField.syncAccountConfig,
        ),
        (
          table: 'app_settings',
          idColumn: 'key',
          field: EncryptedDatabaseField.appSettingValue,
        ),
      ];
  for (final protected in protectedRows) {
    for (final row in await database.query(protected.table)) {
      final id = row[protected.idColumn]! as String;
      expect(
        crypto.decryptField(
          row[protected.field.column] as List<int>,
          field: protected.field,
          rowId: id,
        ),
        expected['$id.${protected.field.column}'],
      );
    }
  }
}

class _FfiMigrationDatabaseFactory implements MigrationDatabaseFactory {
  const _FfiMigrationDatabaseFactory();

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

class _MigrationHarness {
  _MigrationHarness({bool corruptNoteContent = false})
    : keys = DatabaseSessionKeys(
        databaseKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
        fieldKey: Uint8List.fromList(List<int>.generate(32, (i) => 0x80 + i)),
      ) {
    keyStore.replace(keys);
    crypto = AesGcmFieldCrypto(sessionKeyStore: keyStore);
    migrator = LegacyDatabaseMigrator(
      databaseFactory: const _FfiMigrationDatabaseFactory(),
      cryptoService: corruptNoteContent
          ? _CorruptingCryptoService(crypto)
          : crypto,
      now: () => DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000),
    );
  }

  final DatabaseSessionKeyStore keyStore = DatabaseSessionKeyStore();
  final DatabaseSessionKeys keys;
  late final AesGcmFieldCrypto crypto;
  late final LegacyDatabaseMigrator migrator;

  void dispose() {
    keyStore.clear();
  }
}

class _CorruptingCryptoService implements CryptoService {
  const _CorruptingCryptoService(this.delegate);

  final CryptoService delegate;

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    final value =
        context.table == 'note_items' &&
            context.rowId == 'note-1' &&
            context.column == 'content_ciphertext'
        ? '$plaintext changed'
        : plaintext;
    return delegate.encryptNullable(value, context: context);
  }

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return delegate.decryptNullable(ciphertext, context: context);
  }
}
