import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v6_migration.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v7.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v7_migration.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v7 migration checksum covers the normalized delta', () {
    final normalized = DatabaseSchemaV7.migrationStatements
        .map(_normalizeSql)
        .toList(growable: false);

    expect(
      DatabaseSchemaManager.v7MigrationChecksum,
      sha256.convert(utf8.encode(jsonEncode(normalized))).toString(),
    );
  });

  test('v7 target fingerprint matches the locked inventory', () async {
    final fixture = await _DatabaseFixture.create();
    addTearDown(fixture.dispose);
    await fixture.createV6WithChatAndProviders();
    final database = await fixture.openRaw();
    addTearDown(database.close);
    await DatabaseSchemaV7Migration.apply(database);
    await DatabaseSchemaV7Migration.validatePostconditions(database);
    await database.insert('schema_migrations', <String, Object?>{
      'version': 7,
      'name': DatabaseSchemaManager.v7MigrationName,
      'checksum': DatabaseSchemaManager.v7MigrationChecksum,
      'applied_at': 3,
    });

    expect(
      await DatabaseSchemaManager().fingerprint(database),
      DatabaseSchemaManager.expectedFingerprint,
    );
  });

  test('fresh database creates schema v7 privacy boundaries', () async {
    final fixture = await _DatabaseFixture.create();
    addTearDown(fixture.dispose);
    final manager = DatabaseSchemaManager(nowMilliseconds: () => 42);

    final database = await fixture.openManaged(manager);
    addTearDown(database.close);

    expect(await _pragmaInt(database, 'user_version'), 7);
    expect(
      await _columnNames(database, 'chat_messages'),
      containsAll(<String>{
        'actual_backend',
        'actual_model',
        'provider_fingerprint',
      }),
    );
    expect(
      (await database.query(
        'schema_migrations',
        orderBy: 'version ASC',
      )).map((row) => row['version']),
      <Object?>[5, 6, 7],
    );

    await database.insert('provider_configs', _providerRow('provider-a'));
    await expectLater(
      database.insert(
        'provider_configs',
        _providerRow(
          'provider-b',
          providerType: 'openAiCompatible',
          createdAt: 2,
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'v6 to v7 disables providers and leaves historical provenance null',
    () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      await fixture.createV6WithChatAndProviders();
      final manager = DatabaseSchemaManager(nowMilliseconds: () => 84);

      final database = await fixture.openManaged(manager);
      addTearDown(database.close);
      await manager.validate(database);

      expect(await _pragmaInt(database, 'user_version'), 7);
      expect(
        await database.query(
          'provider_configs',
          columns: const <String>['id', 'enabled'],
          orderBy: 'id ASC',
        ),
        const <Map<String, Object?>>[
          <String, Object?>{'id': 'provider-a', 'enabled': 0},
          <String, Object?>{'id': 'provider-b', 'enabled': 0},
        ],
      );
      expect(
        (await database.query('chat_messages')).single,
        containsPair('actual_backend', null),
      );
      expect(
        (await database.query('chat_messages')).single,
        containsPair('actual_model', null),
      );
      expect(
        (await database.query('chat_messages')).single,
        containsPair('provider_fingerprint', null),
      );
      expect(
        (await database.query('chat_messages')).single['content'],
        'historical response',
      );
      expect(
        (await database.query(
          'schema_migrations',
          orderBy: 'version ASC',
        )).map((row) => row['version']),
        <Object?>[5, 6, 7],
      );
      expect(
        await manager.fingerprint(database),
        DatabaseSchemaManager.expectedFingerprint,
      );
    },
  );

  test('v7 checkpoint failure rolls v6 back and retries cleanly', () async {
    final fixture = await _DatabaseFixture.create();
    addTearDown(fixture.dispose);
    await fixture.createV6WithChatAndProviders();
    final failing = DatabaseSchemaManager(
      onMigrationCheckpoint: (checkpoint) async {
        if (checkpoint.name == 'v7SchemaObjectsCreated') {
          throw StateError('injected v7 failure');
        }
      },
    );

    await expectLater(fixture.openManaged(failing), throwsStateError);

    final rolledBack = await fixture.openRaw();
    expect(await _pragmaInt(rolledBack, 'user_version'), 6);
    expect(
      await _columnNames(rolledBack, 'chat_messages'),
      isNot(contains('actual_backend')),
    );
    expect(
      (await rolledBack.query(
        'provider_configs',
        columns: const <String>['enabled'],
      )).map((row) => row['enabled']),
      everyElement(1),
    );
    expect(
      (await rolledBack.query(
        'schema_migrations',
        orderBy: 'version ASC',
      )).map((row) => row['version']),
      <Object?>[5, 6],
    );
    await rolledBack.close();

    final retry = DatabaseSchemaManager();
    final upgraded = await fixture.openManaged(retry);
    addTearDown(upgraded.close);
    await retry.validate(upgraded);
    expect(await _pragmaInt(upgraded, 'user_version'), 7);
  });
}

class _DatabaseFixture {
  _DatabaseFixture(this.directory, this.path);

  final Directory directory;
  final String path;

  static Future<_DatabaseFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_v7_',
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

  Future<void> createV6WithChatAndProviders() async {
    final database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
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
          await database.insert('provider_configs', _providerRow('provider-a'));
          await database.insert(
            'provider_configs',
            _providerRow(
              'provider-b',
              providerType: 'openAiCompatible',
              createdAt: 2,
            ),
          );
          await database.insert('chat_sessions', <String, Object?>{
            'id': 'session-1',
            'mode': 'freeChat',
            'title': 'Historical',
            'allow_private_context': 0,
            'archived': 0,
            'created_at': 1,
            'updated_at': 2,
          });
          await database.insert('chat_messages', <String, Object?>{
            'id': 'message-1',
            'session_id': 'session-1',
            'role': 'assistant',
            'content': 'historical response',
            'status': 'completed',
            'used_private_context': 0,
            'manual_context_item_ids_json': '[]',
            'related_source_ids_json': '[]',
            'created_at': 2,
          });
          await database.insert('schema_migrations', <String, Object?>{
            'version': 5,
            'name': DatabaseSchemaManager.v5MigrationName,
            'checksum': DatabaseSchemaManager.v5MigrationChecksum,
            'applied_at': 1,
          });
          await DatabaseSchemaV6Migration.apply(database);
          await database.insert('schema_migrations', <String, Object?>{
            'version': 6,
            'name': DatabaseSchemaManager.v6MigrationName,
            'checksum': DatabaseSchemaManager.v6MigrationChecksum,
            'applied_at': 2,
          });
        },
      ),
    );
    await database.close();
  }

  Future<void> dispose() => directory.delete(recursive: true);
}

Map<String, Object?> _providerRow(
  String id, {
  String providerType = 'ollama',
  int createdAt = 1,
}) {
  return <String, Object?>{
    'id': id,
    'provider_type': providerType,
    'name': id,
    'encrypted_config': Uint8List.fromList(<int>[createdAt]),
    'enabled': 1,
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

Future<int> _pragmaInt(Database database, String pragma) async {
  final row = (await database.rawQuery('PRAGMA $pragma')).single;
  return row.values.single as int;
}

Future<Set<String>> _columnNames(Database database, String table) async {
  final rows = await database.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name']! as String).toSet();
}

String _normalizeSql(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
