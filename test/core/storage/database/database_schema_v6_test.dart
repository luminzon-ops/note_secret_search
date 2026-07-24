import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v6.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v6 migration checksum covers the normalized final delta', () {
    final normalized = DatabaseSchemaV6.createStatements
        .map(_normalizeSql)
        .toList(growable: false);

    expect(
      DatabaseSchemaManager.v6MigrationChecksum,
      sha256.convert(utf8.encode(jsonEncode(normalized))).toString(),
    );
  });

  test(
    'fresh database creates validated schema v8 with ordered ledger',
    () async {
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
        containsAll(<String>{'embedding_index_sets', 'embedding_chunks'}),
      );
      expect(
        await _columnNames(database, 'embedding_index_sets'),
        containsAll(
          <String>{
            'source_field',
            'model_revision_hash',
            'source_fingerprint',
            'index_config_epoch',
            'chunk_schema_version',
            'vector_dimension',
          }.where((column) => column != 'source_field'),
        ),
      );
      expect(
        await _columnNames(database, 'embedding_chunks'),
        containsAll(<String>{
          'index_set_id',
          'source_field',
          'field_chunk_index',
          'chunk_fingerprint',
          'vector_blob',
        }),
      );
      expect(
        await _columnNames(database, 'embedding_chunks'),
        isNot(contains('plaintext_hash')),
      );
    },
  );

  test(
    'v5 to v8 discards legacy JSON vectors and keeps business data',
    () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      await fixture.createV5WithLegacyEmbedding();

      final manager = DatabaseSchemaManager(nowMilliseconds: () => 84);
      final database = await fixture.openManaged(manager);
      addTearDown(database.close);

      expect(await _pragmaInt(database, 'user_version'), 8);
      expect(await database.query('embedding_index_sets'), isEmpty);
      expect(await database.query('embedding_chunks'), isEmpty);
      expect(
        (await database.query(
          'secret_items',
          columns: const <String>['title'],
          where: 'id = ?',
          whereArgs: const <Object>['secret-1'],
        )).single['title'],
        'Preserved',
      );
      expect(
        (await database.query(
          'schema_migrations',
          orderBy: 'version ASC',
        )).map((row) => row['version']),
        <Object?>[5, 6, 7, 8],
      );
    },
  );

  test('v6 checkpoint failure rolls v5 migration back and retries', () async {
    final fixture = await _DatabaseFixture.create();
    addTearDown(fixture.dispose);
    await fixture.createV5WithLegacyEmbedding();
    final failing = DatabaseSchemaManager(
      onMigrationCheckpoint: (checkpoint) async {
        if (checkpoint == DatabaseMigrationCheckpoint.v6SchemaObjectsCreated) {
          throw StateError('injected v6 failure');
        }
      },
    );

    await expectLater(fixture.openManaged(failing), throwsStateError);

    final rolledBack = await fixture.openRaw();
    expect(await _pragmaInt(rolledBack, 'user_version'), 5);
    expect(await rolledBack.query('embedding_chunks'), hasLength(1));
    expect(
      await _tableNames(rolledBack),
      isNot(contains('embedding_index_sets')),
    );
    await rolledBack.close();

    final retry = DatabaseSchemaManager();
    final upgraded = await fixture.openManaged(retry);
    addTearDown(upgraded.close);
    await retry.validate(upgraded);
    expect(await _pragmaInt(upgraded, 'user_version'), 8);
    expect(await upgraded.query('embedding_chunks'), isEmpty);
  });

  test(
    'v6 enforces field generations and precise source invalidation',
    () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      final database = await fixture.openManaged(DatabaseSchemaManager());
      addTearDown(database.close);
      await _insertSearchOwners(database);

      await database.insert(
        'embedding_index_sets',
        _indexSetRow(chunkCount: 1, vectorDimension: 2),
      );
      await database.insert('embedding_chunks', <String, Object?>{
        'id': 'chunk-1',
        'index_set_id': 'set-1',
        'source_field': 'secret.title',
        'field_chunk_index': 0,
        'chunk_fingerprint': Uint8List(32),
        'vector_blob': Uint8List(8),
        'token_count': 1,
        'created_at': 1,
      });

      await expectLater(
        database.insert('embedding_chunks', <String, Object?>{
          'id': 'wrong-field',
          'index_set_id': 'set-1',
          'source_field': 'note.body',
          'field_chunk_index': 1,
          'chunk_fingerprint': Uint8List(32),
          'vector_blob': Uint8List(8),
          'token_count': 1,
          'created_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('embedding_chunks', <String, Object?>{
          'id': 'wrong-dimension',
          'index_set_id': 'set-1',
          'source_field': 'secret.tags',
          'field_chunk_index': 0,
          'chunk_fingerprint': Uint8List(32),
          'vector_blob': Uint8List(4),
          'token_count': 1,
          'created_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );

      await database.update(
        'secret_items',
        <String, Object?>{
          'password_ciphertext': Uint8List.fromList(<int>[7]),
        },
        where: 'id = ?',
        whereArgs: const <Object>['secret-1'],
      );
      expect(await database.query('embedding_index_sets'), hasLength(1));

      await database.update(
        'secret_items',
        const <String, Object?>{'title': 'Changed'},
        where: 'id = ?',
        whereArgs: const <Object>['secret-1'],
      );
      expect(await database.query('embedding_index_sets'), isEmpty);
      expect(await database.query('embedding_chunks'), isEmpty);

      await database.insert(
        'embedding_index_sets',
        _indexSetRow(chunkCount: 0, vectorDimension: 0),
      );
      expect(await database.query('embedding_index_sets'), hasLength(1));

      await database.update(
        'model_registry',
        const <String, Object?>{'version': '2'},
        where: 'id = ?',
        whereArgs: const <Object>['model-1'],
      );
      expect(await database.query('embedding_index_sets'), isEmpty);
    },
  );
}

class _DatabaseFixture {
  _DatabaseFixture(this.directory, this.path);

  final Directory directory;
  final String path;

  static Future<_DatabaseFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_v6_',
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

  Future<void> createV5WithLegacyEmbedding() async {
    final database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        singleInstance: false,
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
          await database.insert('secret_items', <String, Object?>{
            'id': 'secret-1',
            'vault_id': 'default',
            'title': 'Preserved',
            'favorite': 0,
            'created_at': 1,
            'updated_at': 1,
          });
          await database.insert('model_registry', <String, Object?>{
            'id': 'model-1',
            'type': 'embedding',
            'provider': 'local',
            'name': 'Embedding',
            'integrity_status': 'valid',
            'enabled': 1,
          });
          await database.insert('embedding_chunks', <String, Object?>{
            'id': 'legacy-chunk',
            'source_id': 'secret-1',
            'source_type': 'secret',
            'chunk_index': 0,
            'plaintext_hash': 'reversible',
            'model_id': 'model-1',
            'vector_blob': Uint8List.fromList('[1.0,0.0]'.codeUnits),
            'token_count': 2,
            'created_at': 1,
            'updated_at': 1,
          });
          await database.insert('schema_migrations', <String, Object?>{
            'version': 5,
            'name': DatabaseSchemaManager.v5MigrationName,
            'checksum': DatabaseSchemaManager.v5MigrationChecksum,
            'applied_at': 1,
          });
        },
      ),
    );
    await database.close();
  }

  Future<void> dispose() => directory.delete(recursive: true);
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

Future<void> _insertSearchOwners(Database database) async {
  await database.insert('secret_items', <String, Object?>{
    'id': 'secret-1',
    'vault_id': 'default',
    'title': 'Secret',
    'favorite': 0,
    'created_at': 1,
    'updated_at': 1,
  });
  await database.insert('model_registry', <String, Object?>{
    'id': 'model-1',
    'type': 'embedding',
    'provider': 'local',
    'name': 'Embedding',
    'version': '1',
    'integrity_status': 'unknown',
    'enabled': 0,
  });
}

Map<String, Object?> _indexSetRow({
  required int chunkCount,
  required int vectorDimension,
}) {
  return <String, Object?>{
    'id': 'set-1',
    'source_type': 'secret',
    'source_id': 'secret-1',
    'vault_id': 'default',
    'model_id': 'model-1',
    'model_revision_hash': 'a' * 64,
    'source_updated_at': 1,
    'source_fingerprint': Uint8List(32),
    'fingerprint_key_id': 'key-1',
    'fingerprint_version': 1,
    'index_config_version': 1,
    'index_config_epoch': 0,
    'index_config_hash': 'b' * 64,
    'chunk_schema_version': 1,
    'vector_format_version': 1,
    'vector_dimension': vectorDimension,
    'chunk_count': chunkCount,
    'created_at': 1,
  };
}

String _normalizeSql(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
