import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/migration/frozen_database_schema_v4.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/legacy_database_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  for (final testCase in const <_FixtureCase>[
    _FixtureCase(
      version: LegacyFixtureVersion.v1,
      schemaVersion: 1,
      tables: _v1Tables,
      modelColumns: _modelColumnsV1,
    ),
    _FixtureCase(
      version: LegacyFixtureVersion.v2,
      schemaVersion: 2,
      tables: _v2Tables,
      modelColumns: _modelColumnsV1,
    ),
    _FixtureCase(
      version: LegacyFixtureVersion.upgradedV3,
      schemaVersion: 3,
      tables: _v2Tables,
      modelColumns: _modelColumnsUpgradedV3,
    ),
    _FixtureCase(
      version: LegacyFixtureVersion.freshV3,
      schemaVersion: 3,
      tables: _v2Tables,
      modelColumns: _modelColumnsFreshV3,
    ),
    _FixtureCase(
      version: LegacyFixtureVersion.upgradedV4,
      schemaVersion: 4,
      tables: _v4Tables,
      modelColumns: _modelColumnsUpgradedV3,
    ),
    _FixtureCase(
      version: LegacyFixtureVersion.freshV4,
      schemaVersion: 4,
      tables: _v4Tables,
      modelColumns: _modelColumnsFreshV3,
    ),
    _FixtureCase(
      version: LegacyFixtureVersion.phase2MigratedV4,
      schemaVersion: 4,
      tables: _v4Tables,
      modelColumns: _modelColumnsFreshV3,
    ),
  ]) {
    test(
      '${testCase.version.name} fixture has frozen schema inventory',
      () async {
        final fixture = await createLegacyDatabaseFixture(testCase.version);
        addTearDown(fixture.dispose);
        final database = await databaseFactoryFfi.openDatabase(
          fixture.sourcePath,
        );
        addTearDown(database.close);

        expect(await _userVersion(database), testCase.schemaVersion);
        expect(await _tableNames(database), testCase.tables);
        expect(
          await _columnNames(database, 'model_registry'),
          testCase.modelColumns,
        );
      },
    );
  }

  test('Phase 2 pending copier creates the frozen v4 schema only', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);

    for (final statement in FrozenDatabaseSchemaV4.createStatements) {
      await database.execute(statement);
    }

    expect(await _tableNames(database), _v4Tables);
    expect(
      await _columnNames(database, 'model_registry'),
      _modelColumnsFreshV3,
    );
    expect(
      await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = 'schema_migrations'",
      ),
      isEmpty,
    );
  });

  test('phase2MigratedV4 is produced by the real copier contract', () async {
    final fixture = await createLegacyDatabaseFixture(
      LegacyFixtureVersion.phase2MigratedV4,
    );
    addTearDown(fixture.dispose);
    final database = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
    addTearDown(database.close);

    expect(await database.query('embedding_chunks'), isEmpty);
    expect(await database.query('download_tasks'), isEmpty);
    expect(await database.query('model_catalog_entries'), isEmpty);
    expect(await database.query('security_metadata'), hasLength(1));
    final secret = (await database.query(
      'secret_items',
      where: 'id = ?',
      whereArgs: const <Object>['secret-1'],
    )).single;
    expect(secret['username_ciphertext'], isNot(utf8.encode('alice')));
  });

  test('freshV4 uses canonical current domain values', () async {
    final fixture = await createLegacyDatabaseFixture(
      LegacyFixtureVersion.freshV4,
    );
    addTearDown(fixture.dispose);
    final database = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
    addTearDown(database.close);

    final model = (await database.query('model_registry')).single;
    expect(jsonDecode(model['artifact_paths_json']! as String), <Object?>[
      <String, Object?>{'role': 'model', 'local_path': '/models/legacy.onnx'},
    ]);
    expect(
      (await database.query('download_tasks')).single['status'],
      'downloading',
    );
    expect((await database.query('chat_sessions')).single['mode'], 'freeChat');
  });
}

Future<int> _userVersion(Database database) async {
  final row = (await database.rawQuery('PRAGMA user_version')).single;
  return row.values.single as int;
}

Future<Set<String>> _tableNames(Database database) async {
  final rows = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<List<String>> _columnNames(Database database, String table) async {
  final rows = await database.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name']! as String).toList(growable: false);
}

class _FixtureCase {
  const _FixtureCase({
    required this.version,
    required this.schemaVersion,
    required this.tables,
    required this.modelColumns,
  });

  final LegacyFixtureVersion version;
  final int schemaVersion;
  final Set<String> tables;
  final List<String> modelColumns;
}

const _v1Tables = <String>{
  'vaults',
  'secret_items',
  'note_items',
  'tags',
  'item_tags',
  'categories',
  'embedding_chunks',
  'model_registry',
  'model_catalog_entries',
  'download_tasks',
  'provider_configs',
  'sync_accounts',
  'app_settings',
};

const _v2Tables = <String>{..._v1Tables, 'chat_sessions', 'chat_messages'};

const _v4Tables = <String>{..._v2Tables, 'security_metadata'};

const _modelColumnsV1 = <String>[
  'id',
  'type',
  'provider',
  'name',
  'version',
  'size_bytes',
  'quantization',
  'min_ram_mb',
  'recommended_tier',
  'local_path',
  'checksum',
  'enabled',
  'installed_at',
];

const _modelColumnsUpgradedV3 = <String>[
  'id',
  'type',
  'provider',
  'name',
  'version',
  'size_bytes',
  'quantization',
  'min_ram_mb',
  'recommended_tier',
  'local_path',
  'checksum',
  'enabled',
  'installed_at',
  'artifact_paths_json',
];

const _modelColumnsFreshV3 = <String>[
  'id',
  'type',
  'provider',
  'name',
  'version',
  'size_bytes',
  'quantization',
  'min_ram_mb',
  'recommended_tier',
  'local_path',
  'artifact_paths_json',
  'checksum',
  'integrity_status',
  'enabled',
  'installed_at',
];
