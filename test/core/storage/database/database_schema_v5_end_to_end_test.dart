import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/historical_database_schema.dart';
import '../../../support/phase3_database_gate_expectations.dart';
import '../../../support/phase3_database_migration_fixture.dart';
import '../../../support/phase3_database_snapshot.dart';
import '../../../support/phase4_database_gate_expectations.dart';

part 'database_schema_v5_end_to_end_fixture.dart';
part 'database_schema_v5_end_to_end_upgrade_cases.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  _registerDatabaseSchemaV5UpgradeCases();
}

Future<void> _expectPhase2State(
  Database database,
  _MigrationCase testCase,
) async {
  expect(await phase3PragmaInt(database, 'user_version'), 4);
  expect(await database.query('embedding_chunks'), isEmpty);
  expect(await database.query('download_tasks'), isEmpty);
  expect(await database.query('model_catalog_entries'), isEmpty);
  expect(
    (await database.query('security_metadata')).single,
    _expectedSecurityMetadata(testCase.sourceSchemaVersion),
  );
  final model = (await database.query('model_registry')).single;
  expect(model['integrity_status'], testCase.v4IntegrityStatus);
  expect(model['artifact_paths_json'], testCase.v4ArtifactPathsJson);
}

Future<void> _expectLegacySource(
  String sourcePath,
  _MigrationCase testCase,
) async {
  final source = await databaseFactoryFfi.openDatabase(
    sourcePath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    expect(
      await phase3PragmaInt(source, 'user_version'),
      testCase.sourceSchemaVersion,
    );
    expect(await source.query('embedding_chunks'), hasLength(1));
    expect(await source.query('download_tasks'), hasLength(1));
    expect(await source.query('model_catalog_entries'), hasLength(1));
  } finally {
    await source.close();
  }
}

Future<void> _expectBusinessData(
  Database database, {
  required Phase3DatabaseMigrationFixture fixture,
  required _MigrationCase testCase,
  required Map<String, String?> protectedBytes,
  required String expectedCanonicalDigest,
}) async {
  expect(await capturePhase3ProtectedBytes(database), protectedBytes);
  expect(
    await phase3CanonicalDataDigest(database, fixture.crypto),
    expectedCanonicalDigest,
  );
  expect(await _ids(database, 'vaults'), const <String>['vault-1']);
  expect(await _ids(database, 'categories'), const <String>['category-1']);
  expect(await _ids(database, 'tags'), const <String>['tag-1']);
  expect(await _ids(database, 'secret_items'), const <String>[
    'secret-1',
    'secret-deleted',
  ]);
  expect(await _ids(database, 'note_items'), const <String>[
    'note-1',
    'note-deleted',
  ]);
  expect(await _ids(database, 'model_registry'), const <String>['model-1']);
  expect(await _ids(database, 'provider_configs'), const <String>[
    'provider-1',
  ]);
  expect(await _ids(database, 'sync_accounts'), const <String>['sync-1']);
  expect(
    await database.query('app_settings', columns: const <String>['key']),
    const <Map<String, Object?>>[
      <String, Object?>{'key': 'search.scope'},
    ],
  );
  expect(
    await database.query(
      'item_tags',
      orderBy: 'item_type ASC, item_id ASC, tag_id ASC',
    ),
    const <Map<String, Object?>>[
      <String, Object?>{
        'item_id': 'note-1',
        'item_type': 'note',
        'tag_id': 'tag-1',
      },
      <String, Object?>{
        'item_id': 'secret-1',
        'item_type': 'secret',
        'tag_id': 'tag-1',
      },
    ],
  );

  await _expectTimestamps(database);
  await _expectProtectedPlaintext(database, fixture);

  expect(await database.query('embedding_index_sets'), isEmpty);
  expect(await database.query('embedding_chunks'), isEmpty);
  expect(await database.query('download_tasks'), isEmpty);
  expect(await database.query('model_catalog_entries'), isEmpty);
  expect(
    (await database.query('security_metadata')).single,
    _expectedSecurityMetadata(testCase.sourceSchemaVersion),
  );
  final model = (await database.query('model_registry')).single;
  expect(model['integrity_status'], 'unknown');
  expect(model['enabled'], 0);
  expect(model['active_release_id'], isNull);
  expect(model['catalog_version'], isNull);
  expect(model['catalog_digest'], isNull);
  expect(model['install_generation'], 0);
  expect(model['revision_root'], isNull);
  if (testCase.v5ArtifactPaths == null) {
    expect(model['artifact_paths_json'], isNull);
  } else {
    expect(
      jsonDecode(model['artifact_paths_json']! as String),
      testCase.v5ArtifactPaths,
    );
  }

  final chatSessions = await database.query('chat_sessions');
  final chatMessages = await database.query('chat_messages');
  if (testCase.hasChat) {
    expect(chatSessions.single['id'], 'chat-1');
    expect(chatSessions.single['updated_at'], 1_700_000_000_012);
    expect(chatMessages.single['id'], 'message-1');
    expect(chatMessages.single['created_at'], 1_700_000_000_000);
  } else {
    expect(chatSessions, isEmpty);
    expect(chatMessages, isEmpty);
  }
}

Future<void> _expectTimestamps(Database database) async {
  final vault = (await database.query('vaults')).single;
  expect(vault['created_at'], 1_700_000_000_000);
  expect(vault['updated_at'], 1_700_000_000_001);
  expect(
    (await database.query('tags')).single['created_at'],
    1_700_000_000_000,
  );
  expect(
    await database.query(
      'secret_items',
      columns: const <String>[
        'id',
        'created_at',
        'updated_at',
        'last_accessed_at',
        'deleted_at',
      ],
      orderBy: 'id ASC',
    ),
    const <Map<String, Object?>>[
      <String, Object?>{
        'id': 'secret-1',
        'created_at': 1_700_000_000_000,
        'updated_at': 1_700_000_000_002,
        'last_accessed_at': 1_700_000_000_003,
        'deleted_at': null,
      },
      <String, Object?>{
        'id': 'secret-deleted',
        'created_at': 1_700_000_000_000,
        'updated_at': 1_700_000_000_004,
        'last_accessed_at': null,
        'deleted_at': 1_700_000_000_005,
      },
    ],
  );
  expect(
    await database.query(
      'note_items',
      columns: const <String>['id', 'created_at', 'updated_at', 'deleted_at'],
      orderBy: 'id ASC',
    ),
    const <Map<String, Object?>>[
      <String, Object?>{
        'id': 'note-1',
        'created_at': 1_700_000_000_000,
        'updated_at': 1_700_000_000_006,
        'deleted_at': null,
      },
      <String, Object?>{
        'id': 'note-deleted',
        'created_at': 1_700_000_000_000,
        'updated_at': 1_700_000_000_007,
        'deleted_at': 1_700_000_000_008,
      },
    ],
  );
  final provider = (await database.query('provider_configs')).single;
  expect(provider['created_at'], 1_700_000_000_000);
  expect(provider['updated_at'], 1_700_000_000_009);
  expect(provider['enabled'], 0);
  final sync = (await database.query('sync_accounts')).single;
  expect(sync['last_sync_at'], 1_700_000_000_010);
  expect(sync['updated_at'], 1_700_000_000_011);
  expect(
    (await database.query('model_registry')).single['installed_at'],
    1_700_000_000_000,
  );
}

Future<void> _expectProtectedPlaintext(
  Database database,
  Phase3DatabaseMigrationFixture fixture,
) async {
  for (final tableFields in const <String, List<EncryptedDatabaseField>>{
    'secret_items': <EncryptedDatabaseField>[
      EncryptedDatabaseField.secretUsername,
      EncryptedDatabaseField.secretPassword,
      EncryptedDatabaseField.secretWebsiteUrl,
      EncryptedDatabaseField.secretNote,
    ],
    'note_items': <EncryptedDatabaseField>[
      EncryptedDatabaseField.noteContent,
      EncryptedDatabaseField.noteSummary,
    ],
  }.entries) {
    for (final row in await database.query(tableFields.key)) {
      final id = row['id']! as String;
      for (final field in tableFields.value) {
        final expected = phase3ExpectedPlaintext['$id.${field.column}'];
        final bytes = row[field.column] as List<int>?;
        if (expected == null) {
          expect(bytes, isNull);
        } else {
          expect(
            fixture.crypto.decryptField(bytes, field: field, rowId: id),
            expected,
          );
        }
      }
    }
  }
  for (final protected
      in const <
        ({String table, String idColumn, EncryptedDatabaseField field})
      >[
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
      ]) {
    final row = (await database.query(protected.table)).single;
    final id = row[protected.idColumn]! as String;
    expect(
      fixture.crypto.decryptField(
        row[protected.field.column] as List<int>,
        field: protected.field,
        rowId: id,
      ),
      phase3ExpectedPlaintext['$id.${protected.field.column}'],
    );
  }
}

Future<void> _expectSchemaGate(
  Database database,
  DatabaseSchemaManager manager,
) async {
  expect(await phase3PragmaInt(database, 'user_version'), 8);
  expect(await phase3PragmaInt(database, 'foreign_keys'), 1);
  expect(
    (await database.rawQuery('PRAGMA quick_check')).single.values.single,
    'ok',
  );
  expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  expect(await phase3ObjectNames(database, 'table'), <String>{
    ...phase4V6Tables,
    'model_catalog_state',
    'model_registry_artifacts',
    'model_install_journal',
  });
  expect(await phase3ObjectNames(database, 'index'), <String>{
    ...phase4V6Indexes,
    'idx_model_registry_artifacts_model_release',
    'uq_download_tasks_identity',
    'idx_download_tasks_operation_checkpoint',
    'idx_model_install_journal_model_phase',
  });
  expect(await phase3ObjectNames(database, 'trigger'), <String>{
    ...phase4V6Triggers,
    'trg_model_registry_trusted_insert',
    'trg_model_registry_trusted_update',
  });
  expect(
    await manager.fingerprint(database),
    DatabaseSchemaManager.expectedFingerprint,
  );
  expect(
    await database.query('schema_migrations', orderBy: 'version ASC'),
    <Map<String, Object?>>[
      <String, Object?>{
        'version': 5,
        'name': phase3ExpectedMigrationName,
        'checksum': phase3ExpectedMigrationChecksum,
        'applied_at': 1_800_000_000_000,
      },
      <String, Object?>{
        'version': 6,
        'name': DatabaseSchemaManager.v6MigrationName,
        'checksum': DatabaseSchemaManager.v6MigrationChecksum,
        'applied_at': 1_800_000_000_000,
      },
      <String, Object?>{
        'version': 7,
        'name': DatabaseSchemaManager.v7MigrationName,
        'checksum': DatabaseSchemaManager.v7MigrationChecksum,
        'applied_at': 1_800_000_000_000,
      },
      <String, Object?>{
        'version': 8,
        'name': DatabaseSchemaManager.v8MigrationName,
        'checksum': DatabaseSchemaManager.v8MigrationChecksum,
        'applied_at': 1_800_000_000_000,
      },
    ],
  );
  for (final queryCase in phase3QueryPlanCases) {
    final details = await phase3QueryPlanDetails(
      database,
      queryCase.sql,
      queryCase.arguments,
    );
    expect(details, contains(contains(queryCase.indexName)));
    expect(details, isNot(contains(contains('USE TEMP B-TREE'))));
  }
}

Future<List<String>> _ids(Database database, String table) async {
  final rows = await database.query(
    table,
    columns: const <String>['id'],
    orderBy: 'id ASC',
  );
  return rows.map((row) => row['id']! as String).toList(growable: false);
}

Map<String, Object?> _expectedSecurityMetadata(int sourceSchemaVersion) {
  return <String, Object?>{
    'key_id': '123e4567-e89b-42d3-a456-426614174000',
    'source_schema_version': sourceSchemaVersion,
    'field_envelope_version': 1,
    'migration_state': 'validated',
    'migrated_at': 1_700_000_000_013,
  };
}

Future<Database> _openManagedDatabase(
  String path,
  DatabaseSchemaManager manager,
) {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: DatabaseSchemaManager.latestVersion,
      onConfigure: manager.configure,
      onCreate: manager.create,
      onUpgrade: manager.upgrade,
      onDowngrade: manager.downgrade,
      singleInstance: false,
    ),
  );
}
