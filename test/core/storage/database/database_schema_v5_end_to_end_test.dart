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

void main() {
  setUpAll(sqfliteFfiInit);

  for (final testCase in _migrationCases) {
    test(
      '${testCase.name} upgrades through frozen v4 into validated v6',
      () async {
        final fixture = await createPhase3DatabaseMigrationFixture(
          testCase.version,
        );
        addTearDown(fixture.dispose);
        await _expectLegacySource(fixture.sourcePath, testCase);

        final v4 = await databaseFactoryFfi.openDatabase(
          fixture.databasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        late final Map<String, String?> protectedBytes;
        late final String canonicalDigest;
        try {
          protectedBytes = await capturePhase3ProtectedBytes(v4);
          canonicalDigest = await phase3CanonicalDataDigest(v4, fixture.crypto);
          expect(canonicalDigest, testCase.expectedCanonicalDigest);
          await _expectPhase2State(v4, testCase);
        } finally {
          await v4.close();
        }

        final manager = DatabaseSchemaManager(
          nowMilliseconds: () => 1_800_000_000_000,
        );
        final v6 = await _openManagedDatabase(fixture.databasePath, manager);
        addTearDown(v6.close);

        await manager.validate(v6);
        await _expectBusinessData(
          v6,
          fixture: fixture,
          testCase: testCase,
          protectedBytes: protectedBytes,
          canonicalDigest: canonicalDigest,
        );
        await _expectSchemaGate(v6, manager);
      },
    );
  }
}

Future<void> _expectPhase2State(
  Database database,
  _MigrationCase testCase,
) async {
  expect(await phase3PragmaInt(database, 'user_version'), 4);
  expect(await database.query('embedding_chunks'), isEmpty);
  expect(await database.query('embedding_index_sets'), isEmpty);
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
  required String canonicalDigest,
}) async {
  expect(await capturePhase3ProtectedBytes(database), protectedBytes);
  expect(
    await phase3CanonicalDataDigest(database, fixture.crypto),
    canonicalDigest,
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

  expect(await database.query('embedding_chunks'), isEmpty);
  expect(await database.query('download_tasks'), isEmpty);
  expect(await database.query('model_catalog_entries'), isEmpty);
  expect(
    (await database.query('security_metadata')).single,
    _expectedSecurityMetadata(testCase.sourceSchemaVersion),
  );
  final model = (await database.query('model_registry')).single;
  expect(model['integrity_status'], testCase.v5IntegrityStatus);
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
  expect(await phase3PragmaInt(database, 'user_version'), 6);
  expect(await phase3PragmaInt(database, 'foreign_keys'), 1);
  expect(
    (await database.rawQuery('PRAGMA quick_check')).single.values.single,
    'ok',
  );
  expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  expect(await phase3ObjectNames(database, 'table'), phase4V6Tables);
  expect(await phase3ObjectNames(database, 'index'), phase4V6Indexes);
  expect(await phase3ObjectNames(database, 'trigger'), phase4V6Triggers);
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

class _MigrationCase {
  const _MigrationCase({
    required this.version,
    required this.name,
    required this.sourceSchemaVersion,
    required this.hasChat,
    required this.v4IntegrityStatus,
    required this.v4ArtifactPathsJson,
    required this.v5IntegrityStatus,
    required this.v5ArtifactPaths,
    required this.expectedCanonicalDigest,
  });

  final LegacyFixtureVersion version;
  final String name;
  final int sourceSchemaVersion;
  final bool hasChat;
  final String v4IntegrityStatus;
  final String? v4ArtifactPathsJson;
  final String v5IntegrityStatus;
  final List<Object?>? v5ArtifactPaths;
  final String expectedCanonicalDigest;
}

const _structuredModelArtifact = <Object?>[
  <String, Object?>{'role': 'model', 'local_path': '/models/legacy.onnx'},
];

const _migrationCases = <_MigrationCase>[
  _MigrationCase(
    version: LegacyFixtureVersion.v1,
    name: 'v1',
    sourceSchemaVersion: 1,
    hasChat: false,
    v4IntegrityStatus: 'unknown',
    v4ArtifactPathsJson: null,
    v5IntegrityStatus: 'unknown',
    v5ArtifactPaths: null,
    expectedCanonicalDigest:
        'f17d452ee9d4022c9e9a932545675733'
        'd3b1f51d513bce0f1bd6ea94ffab2b16',
  ),
  _MigrationCase(
    version: LegacyFixtureVersion.v2,
    name: 'v2',
    sourceSchemaVersion: 2,
    hasChat: true,
    v4IntegrityStatus: 'unknown',
    v4ArtifactPathsJson: null,
    v5IntegrityStatus: 'unknown',
    v5ArtifactPaths: null,
    expectedCanonicalDigest:
        '292f3defcbc27c02e341f7eea25a7cff'
        '2c2293896112f60091a78c76fe3a1985',
  ),
  _MigrationCase(
    version: LegacyFixtureVersion.upgradedV3,
    name: 'upgraded v3',
    sourceSchemaVersion: 3,
    hasChat: true,
    v4IntegrityStatus: 'unknown',
    v4ArtifactPathsJson: '["/models/legacy.onnx"]',
    v5IntegrityStatus: 'unknown',
    v5ArtifactPaths: _structuredModelArtifact,
    expectedCanonicalDigest:
        'd20cdb0230f26d4f387d16add55c5a3'
        'e09ce58784f61736eef5fa9729b4a2f82',
  ),
  _MigrationCase(
    version: LegacyFixtureVersion.freshV3,
    name: 'fresh v3',
    sourceSchemaVersion: 3,
    hasChat: true,
    v4IntegrityStatus: 'verified',
    v4ArtifactPathsJson: '["/models/legacy.onnx"]',
    v5IntegrityStatus: 'valid',
    v5ArtifactPaths: _structuredModelArtifact,
    expectedCanonicalDigest:
        'c4077e096892228b9a69c6562c1cbccf'
        '5b8d9b8b9cf5a8cd98e404c57f076400',
  ),
];
