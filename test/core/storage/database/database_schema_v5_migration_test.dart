import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/legacy_database_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  for (final failingCheckpoint in DatabaseMigrationCheckpoint.values) {
    test(
      'v4 upgrade rolls back at ${failingCheckpoint.name} and retries',
      () async {
        final fixture = await createLegacyDatabaseFixture(
          LegacyFixtureVersion.upgradedV4,
        );
        addTearDown(fixture.dispose);
        final before = sha256.convert(
          await File(fixture.sourcePath).readAsBytes(),
        );
        final failingManager = DatabaseSchemaManager(
          onMigrationCheckpoint: (checkpoint) async {
            if (checkpoint == failingCheckpoint) {
              throw StateError('injected checkpoint failure');
            }
          },
        );

        await expectLater(
          _openManagedDatabase(fixture.sourcePath, failingManager),
          throwsA(isA<StateError>()),
        );

        expect(
          sha256.convert(await File(fixture.sourcePath).readAsBytes()),
          before,
        );
        final rolledBack = await databaseFactoryFfi.openDatabase(
          fixture.sourcePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        expect(await _pragmaInt(rolledBack, 'user_version'), 4);
        expect(
          await _columnNames(rolledBack, 'model_registry'),
          isNot(contains('integrity_status')),
        );
        expect(
          await _tableNames(rolledBack),
          isNot(contains('schema_migrations')),
        );
        expect(
          await _tableNames(rolledBack),
          everyElement(isNot(startsWith('__v4_'))),
        );
        await rolledBack.close();

        final retryManager = DatabaseSchemaManager();
        final upgraded = await _openManagedDatabase(
          fixture.sourcePath,
          retryManager,
        );
        addTearDown(upgraded.close);

        await retryManager.validate(upgraded);
        expect(await _pragmaInt(upgraded, 'user_version'), 5);
      },
    );
  }

  for (final invalidCase in <_InvalidV4Case>[
    _InvalidV4Case(
      name: 'malformed artifact JSON',
      mutate: (database) {
        return database.update(
          'model_registry',
          <String, Object?>{'artifact_paths_json': '{broken'},
          where: 'id = ?',
          whereArgs: const <Object>['model-1'],
        );
      },
    ),
    _InvalidV4Case(
      name: 'Secret without a Vault',
      mutate: (database) {
        return database.update(
          'secret_items',
          <String, Object?>{'vault_id': 'missing-vault'},
          where: 'id = ?',
          whereArgs: const <Object>['secret-1'],
        );
      },
    ),
    _InvalidV4Case(
      name: 'Note without a Vault',
      mutate: (database) {
        return database.update(
          'note_items',
          <String, Object?>{'vault_id': 'missing-vault'},
          where: 'id = ?',
          whereArgs: const <Object>['note-1'],
        );
      },
    ),
    _InvalidV4Case(
      name: 'chat message without a session',
      mutate: (database) {
        return database.update(
          'chat_messages',
          <String, Object?>{'session_id': 'missing-session'},
          where: 'id = ?',
          whereArgs: const <Object>['message-1'],
        );
      },
    ),
    _InvalidV4Case(
      name: 'invalid historical boolean',
      mutate: (database) {
        return database.update(
          'secret_items',
          <String, Object?>{'favorite': 2},
          where: 'id = ?',
          whereArgs: const <Object>['secret-1'],
        );
      },
    ),
    _InvalidV4Case(
      name: 'column type drift',
      mutate: (database) async {
        final row = (await database.rawQuery('''
          SELECT sql FROM sqlite_master
          WHERE type = 'table' AND name = 'secret_items'
          ''')).single;
        final originalSql = row['sql']! as String;
        final tamperedSql = originalSql.replaceFirst(
          RegExp(r'favorite\s+INTEGER\s+NOT\s+NULL\s+DEFAULT\s+0'),
          'favorite TEXT NOT NULL DEFAULT 0',
        );
        if (tamperedSql == originalSql) {
          throw StateError('favorite column declaration was not found');
        }
        final schemaVersion = await _pragmaInt(database, 'schema_version');
        await database.execute('PRAGMA writable_schema = ON');
        await database.rawUpdate(
          '''
          UPDATE sqlite_master SET sql = ?
          WHERE type = 'table' AND name = 'secret_items'
          ''',
          <Object>[tamperedSql],
        );
        await database.execute('PRAGMA writable_schema = OFF');
        return database.execute('PRAGMA schema_version = ${schemaVersion + 1}');
      },
    ),
  ]) {
    test('${invalidCase.name} aborts migration and preserves v4', () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.freshV4,
      );
      addTearDown(fixture.dispose);
      final raw = await databaseFactoryFfi.openDatabase(
        fixture.sourcePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await invalidCase.mutate(raw);
      await raw.close();
      final before = sha256.convert(
        await File(fixture.sourcePath).readAsBytes(),
      );

      await expectLater(
        _openManagedDatabase(fixture.sourcePath, DatabaseSchemaManager()),
        throwsA(
          isA<DatabaseSchemaException>().having(
            (error) => error.code,
            'code',
            'database_schema_invalid',
          ),
        ),
      );

      expect(
        sha256.convert(await File(fixture.sourcePath).readAsBytes()),
        before,
      );
      final preserved = await databaseFactoryFfi.openDatabase(
        fixture.sourcePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(preserved.close);
      expect(await _pragmaInt(preserved, 'user_version'), 4);
      expect(
        await _tableNames(preserved),
        isNot(contains('schema_migrations')),
      );
      expect(
        await _tableNames(preserved),
        everyElement(isNot(startsWith('__v4_'))),
      );
    });
  }
}

class _InvalidV4Case {
  const _InvalidV4Case({required this.name, required this.mutate});

  final String name;
  final Future<Object?> Function(Database database) mutate;
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

Future<int> _pragmaInt(Database database, String pragma) async {
  final row = (await database.rawQuery('PRAGMA $pragma')).single;
  return row.values.single as int;
}

Future<List<String>> _columnNames(Database database, String table) async {
  final rows = await database.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name']! as String).toList(growable: false);
}

Future<Set<String>> _tableNames(Database database) async {
  final rows = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}
