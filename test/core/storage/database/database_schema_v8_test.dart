import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v6_migration.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v7_migration.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v8.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v8_migration.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v8 migration checksum covers the normalized delta', () {
    final normalized = DatabaseSchemaV8.migrationStatements
        .map(_normalizeSql)
        .toList(growable: false);

    expect(
      DatabaseSchemaManager.v8MigrationChecksum,
      sha256.convert(utf8.encode(jsonEncode(normalized))).toString(),
    );
  });

  test('fresh database creates and validates schema v8', () async {
    final fixture = await _DatabaseFixture.create();
    addTearDown(fixture.dispose);
    final manager = DatabaseSchemaManager(nowMilliseconds: () => 42);

    final database = await fixture.openManaged(manager);
    addTearDown(database.close);
    await manager.validate(database);

    expect(await _pragmaInt(database, 'user_version'), 8);
    expect(
      (await database.query(
        'schema_migrations',
        orderBy: 'version ASC',
      )).map((row) => row['version']),
      <Object?>[5, 6, 7, 8],
    );
    expect(
      await _tableNames(database),
      containsAll(<String>{
        'model_catalog_state',
        'model_registry_artifacts',
        'model_install_journal',
      }),
    );
    expect(
      await _columnNames(database, 'download_tasks'),
      containsAll(<String>{
        'operation_id',
        'attempt_generation',
        'release_id',
        'artifact_id',
        'source_url',
        'staging_path',
        'expected_sha256',
        'expected_size_bytes',
        'etag',
        'last_modified',
        'checkpoint',
        'retry_reason',
        'received_bytes',
      }),
    );
  });

  test('v8 target fingerprint matches the locked inventory', () async {
    final fixture = await _DatabaseFixture.create();
    addTearDown(fixture.dispose);
    await fixture.createV7();
    final database = await fixture.openRaw();
    addTearDown(database.close);

    await DatabaseSchemaV8Migration.apply(database);

    expect(
      await DatabaseSchemaManager().fingerprint(database),
      DatabaseSchemaManager.v8ExpectedFingerprint,
    );
  });

  test(
    'v7 to v8 preserves legacy rows and marks new identity fields legacy',
    () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      await fixture.createV7();

      final manager = DatabaseSchemaManager(nowMilliseconds: () => 84);
      final database = await fixture.openManaged(manager);
      addTearDown(database.close);
      await manager.validate(database);

      expect(await _pragmaInt(database, 'user_version'), 8);
      expect(
        (await database.query(
          'download_tasks',
          where: 'id = ?',
          whereArgs: const <Object>['legacy-task'],
        )).single,
        containsPair('model_id', 'legacy-model'),
      );
      final task = (await database.query(
        'download_tasks',
        where: 'id = ?',
        whereArgs: const <Object>['legacy-task'],
      )).single;
      expect(task['checkpoint'], 'legacy');
      expect(task['received_bytes'], 12);
      expect(task['operation_id'], isNull);
      expect(await database.query('model_catalog_state'), isEmpty);
      expect(await database.query('model_registry_artifacts'), isEmpty);
      expect(await database.query('model_install_journal'), isEmpty);
    },
  );

  test('v8 migration is idempotent when applied twice', () async {
    final fixture = await _DatabaseFixture.create();
    addTearDown(fixture.dispose);
    await fixture.createV7();
    final database = await fixture.openRaw();
    addTearDown(database.close);

    await DatabaseSchemaV8Migration.apply(database);
    final firstTables = await _tableNames(database);
    final firstColumns = await _columnNames(database, 'download_tasks');
    await DatabaseSchemaV8Migration.apply(database);

    expect(await _tableNames(database), firstTables);
    expect(await _columnNames(database, 'download_tasks'), firstColumns);
    expect(
      await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name LIKE 'idx_model_%' ORDER BY name",
      ),
      hasLength(3),
    );
  });

  test(
    'v8 trust tables reject weak digests and unsafe artifact paths',
    () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      final database = await fixture.openManaged(DatabaseSchemaManager());
      addTearDown(database.close);

      await database.insert('model_registry', <String, Object?>{
        'id': 'model-1',
        'type': 'embedding',
        'provider': 'builtin',
        'name': 'Model 1',
        'enabled': 0,
        'integrity_status': 'unknown',
      });

      await expectLater(
        database.insert('model_catalog_state', <String, Object?>{
          'id': 'active',
          'accepted_version': 1,
          'accepted_digest': 'not-a-sha256',
          'accepted_key_id': 'phase7-v1',
          'accepted_schema_version': 1,
          'minimum_accepted_version': 1,
          'updated_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('model_registry_artifacts', <String, Object?>{
          'model_id': 'model-1',
          'release_id': 'release-1',
          'artifact_id': 'model',
          'role': 'model',
          'required': 1,
          'relative_path': '../model.onnx',
          'expected_size_bytes': 1,
          'expected_sha256': 'sha256:${'a' * 64}',
          'state': 'unknown',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('model_registry_artifacts', <String, Object?>{
          'model_id': 'model-1',
          'release_id': 'release-1',
          'artifact_id': 'model',
          'role': 'model',
          'required': 1,
          'relative_path': 'model.onnx',
          'expected_size_bytes': 1,
          'expected_sha256': 'sha256:ABC',
          'state': 'unknown',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}

class _DatabaseFixture {
  _DatabaseFixture(this.directory, this.path);

  final Directory directory;
  final String path;

  static Future<_DatabaseFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_v8_',
    );
    return _DatabaseFixture(directory, p.join(directory.path, 'database.db'));
  }

  Future<Database> openManaged(DatabaseSchemaManager manager) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: manager.version,
        onConfigure: manager.configure,
        onCreate: manager.create,
        onUpgrade: manager.upgrade,
        onDowngrade: manager.downgrade,
        singleInstance: false,
      ),
    );
  }

  Future<Database> openRaw() {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  }

  Future<void> createV7() async {
    final database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        singleInstance: false,
        onConfigure: (database) {
          return database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          final batch = database.batch();
          for (final statement in DatabaseSchemaV5.createStatements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
          await database.insert('vaults', <String, Object?>{
            'id': 'default',
            'name': 'Default',
            'is_default': 1,
            'encryption_version': 1,
            'created_at': 1,
            'updated_at': 1,
          });
          await DatabaseSchemaV6Migration.apply(database);
          await DatabaseSchemaV7Migration.apply(database);
          await database.insert('schema_migrations', <String, Object?>{
            'version': 5,
            'name': DatabaseSchemaManager.v5MigrationName,
            'checksum': DatabaseSchemaManager.v5MigrationChecksum,
            'applied_at': 1,
          });
          await database.insert('schema_migrations', <String, Object?>{
            'version': 6,
            'name': DatabaseSchemaManager.v6MigrationName,
            'checksum': DatabaseSchemaManager.v6MigrationChecksum,
            'applied_at': 2,
          });
          await database.insert('schema_migrations', <String, Object?>{
            'version': 7,
            'name': DatabaseSchemaManager.v7MigrationName,
            'checksum': DatabaseSchemaManager.v7MigrationChecksum,
            'applied_at': 3,
          });
          await database.insert('model_registry', <String, Object?>{
            'id': 'legacy-model',
            'type': 'embedding',
            'provider': 'legacy',
            'name': 'Legacy',
            'enabled': 0,
            'integrity_status': 'unknown',
          });
          await database.insert('download_tasks', <String, Object?>{
            'id': 'legacy-task',
            'model_id': 'legacy-model',
            'source_id': 'legacy-source',
            'status': 'paused',
            'total_bytes': 20,
            'downloaded_bytes': 12,
            'average_speed': null,
            'error_message': null,
            'resumable': 1,
            'created_at': 4,
            'updated_at': 4,
          });
        },
      ),
    );
    await database.close();
  }

  Future<void> dispose() => directory.delete(recursive: true);
}

String _normalizeSql(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

Future<int> _pragmaInt(Database database, String pragma) async {
  final row = (await database.rawQuery('PRAGMA $pragma')).single;
  return row.values.single as int;
}

Future<Set<String>> _tableNames(Database database) async {
  final rows = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _columnNames(Database database, String table) async {
  final rows = await database.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name']! as String).toSet();
}
