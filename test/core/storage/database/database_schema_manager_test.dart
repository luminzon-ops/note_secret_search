import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/legacy_database_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('fresh database creates and validates schema v8', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_v5_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = DatabaseSchemaManager(
      nowMilliseconds: () => 1_800_000_000_000,
    );
    final database = await _openManagedDatabase(
      p.join(directory.path, 'fresh.db'),
      manager,
    );
    addTearDown(database.close);

    await manager.validate(database);

    expect(await _pragmaInt(database, 'user_version'), 8);
    expect(await _pragmaInt(database, 'foreign_keys'), 1);
    expect(
      await database.query(
        'vaults',
        columns: const <String>['id'],
        where: 'is_default = 1',
      ),
      const <Map<String, Object?>>[
        <String, Object?>{'id': 'default'},
      ],
    );
    expect(
      await database.query('schema_migrations', orderBy: 'version ASC'),
      <Map<String, Object?>>[
        <String, Object?>{
          'version': 5,
          'name': DatabaseSchemaManager.v5MigrationName,
          'checksum': DatabaseSchemaManager.v5MigrationChecksum,
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
    expect(
      await manager.fingerprint(database),
      DatabaseSchemaManager.expectedFingerprint,
    );
  });

  test('upgraded v4 reaches v8 without business data loss', () async {
    final fixture = await createLegacyDatabaseFixture(
      LegacyFixtureVersion.upgradedV4,
    );
    addTearDown(fixture.dispose);
    final manager = DatabaseSchemaManager(
      nowMilliseconds: () => 1_800_000_000_001,
    );

    final database = await _openManagedDatabase(fixture.sourcePath, manager);
    addTearDown(database.close);
    await manager.validate(database);

    expect(await _pragmaInt(database, 'user_version'), 8);
    final model = (await database.query('model_registry')).single;
    expect(model['id'], 'model-1');
    expect(model['integrity_status'], 'unknown');
    expect(jsonDecode(model['artifact_paths_json']! as String), <Object?>[
      <String, Object?>{'role': 'model', 'local_path': '/models/legacy.onnx'},
    ]);
    final secret = (await database.query(
      'secret_items',
      where: 'id = ?',
      whereArgs: const <Object>['secret-1'],
    )).single;
    expect(secret['title'], 'Primary account');
    expect(secret['username_ciphertext'], utf8.encode('alice'));
    expect(await database.query('schema_migrations'), hasLength(4));
    expect(
      await manager.fingerprint(database),
      DatabaseSchemaManager.expectedFingerprint,
    );
  });

  test('reopening v8 validates without repeating bootstrap writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_reopen_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'repeated.db');
    final firstManager = DatabaseSchemaManager(
      nowMilliseconds: () => 1_800_000_000_010,
    );
    final first = await _openManagedDatabase(path, firstManager);
    final originalLedger = await first.query('schema_migrations');
    final originalVault = await first.query('vaults');
    await first.close();

    final secondManager = DatabaseSchemaManager(
      nowMilliseconds: () => 1_900_000_000_000,
    );
    final second = await _openManagedDatabase(path, secondManager);
    addTearDown(second.close);
    await secondManager.validate(second);

    expect(await second.query('schema_migrations'), originalLedger);
    expect(await second.query('vaults'), originalVault);
  });

  test('v8 rejects a mismatched migration ledger without mutation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_ledger_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = DatabaseSchemaManager();
    final database = await _openManagedDatabase(
      p.join(directory.path, 'ledger.db'),
      manager,
    );
    addTearDown(database.close);
    await database.update(
      'schema_migrations',
      <String, Object?>{'checksum': 'tampered'},
      where: 'version = ?',
      whereArgs: const <Object>[8],
    );

    await expectLater(
      manager.validate(database),
      throwsA(
        isA<DatabaseSchemaException>().having(
          (error) => error.code,
          'code',
          'database_schema_invalid',
        ),
      ),
    );
    expect(
      (await database.query(
        'schema_migrations',
        where: 'version = ?',
        whereArgs: const <Object>[8],
      )).single['checksum'],
      'tampered',
    );
  });

  test('v8 rejects a mismatched schema fingerprint without repair', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_fingerprint_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = DatabaseSchemaManager();
    final database = await _openManagedDatabase(
      p.join(directory.path, 'fingerprint.db'),
      manager,
    );
    addTearDown(database.close);
    await database.execute('ALTER TABLE vaults ADD COLUMN rogue TEXT');

    await expectLater(
      manager.validate(database),
      throwsA(
        isA<DatabaseSchemaException>().having(
          (error) => error.code,
          'code',
          'database_schema_invalid',
        ),
      ),
    );
    expect(await _columnNames(database, 'vaults'), contains('rogue'));
  });

  test('v8 rejects foreign key corruption without repair', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_foreign_key_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = DatabaseSchemaManager();
    final database = await _openManagedDatabase(
      p.join(directory.path, 'foreign-key.db'),
      manager,
    );
    addTearDown(database.close);
    await database.execute('PRAGMA foreign_keys = OFF');
    await database.insert('secret_items', <String, Object?>{
      'id': 'orphan-secret',
      'vault_id': 'missing-vault',
      'title': 'Orphan',
      'favorite': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await database.execute('PRAGMA foreign_keys = ON');

    expect(await _pragmaInt(database, 'foreign_keys'), 1);
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isNotEmpty);
    await expectLater(
      manager.validate(database),
      throwsA(
        isA<DatabaseSchemaException>().having(
          (error) => error.code,
          'code',
          'database_schema_invalid',
        ),
      ),
    );
    expect(
      await database.query(
        'secret_items',
        where: 'id = ?',
        whereArgs: const <Object>['orphan-secret'],
      ),
      hasLength(1),
    );
  });

  test('v8 rejects a failed quick check', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_quick_check_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = DatabaseSchemaManager();
    final database = await _openManagedDatabase(
      p.join(directory.path, 'quick-check.db'),
      manager,
    );
    addTearDown(database.close);

    await expectLater(
      manager.validate(_QuickCheckFailureDatabase(database)),
      throwsA(
        isA<DatabaseSchemaException>().having(
          (error) => error.code,
          'code',
          'database_schema_invalid',
        ),
      ),
    );
  });

  test('v8 fingerprint includes table CHECK definitions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_check_fingerprint_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = DatabaseSchemaManager();
    final database = await _openManagedDatabase(
      p.join(directory.path, 'check-fingerprint.db'),
      manager,
    );
    addTearDown(database.close);
    final row = (await database.rawQuery('''
      SELECT sql FROM sqlite_master
      WHERE type = 'table' AND name = 'vaults'
      ''')).single;
    final originalSql = row['sql']! as String;
    final tamperedSql = originalSql.replaceFirst(
      RegExp(r'CHECK\s*\(\s*is_default\s+IN\s*\(\s*0\s*,\s*1\s*\)\s*\)'),
      '',
    );
    expect(tamperedSql, isNot(originalSql));
    await database.execute('PRAGMA writable_schema = ON');
    await database.rawUpdate(
      '''
      UPDATE sqlite_master SET sql = ?
      WHERE type = 'table' AND name = 'vaults'
      ''',
      <Object>[tamperedSql],
    );
    await database.execute('PRAGMA writable_schema = OFF');

    await expectLater(
      manager.validate(database),
      throwsA(
        isA<DatabaseSchemaException>().having(
          (error) => error.code,
          'code',
          'database_schema_invalid',
        ),
      ),
    );
  });

  test('v8 rejects a database with no default Vault', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_schema_default_vault_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = DatabaseSchemaManager();
    final database = await _openManagedDatabase(
      p.join(directory.path, 'default-vault.db'),
      manager,
    );
    addTearDown(database.close);
    await database.update(
      'vaults',
      const <String, Object?>{'is_default': 0},
      where: 'id = ?',
      whereArgs: const <Object>['default'],
    );

    await expectLater(
      manager.validate(database),
      throwsA(
        isA<DatabaseSchemaException>().having(
          (error) => error.code,
          'code',
          'database_schema_invalid',
        ),
      ),
    );
  });

  test('direct v3 open is rejected and remains v3 for Phase 2', () async {
    final fixture = await createLegacyDatabaseFixture(
      LegacyFixtureVersion.freshV3,
    );
    addTearDown(fixture.dispose);
    final before = sha256.convert(await File(fixture.sourcePath).readAsBytes());

    await expectLater(
      _openManagedDatabase(fixture.sourcePath, DatabaseSchemaManager()),
      throwsA(
        isA<DatabaseSchemaException>().having(
          (error) => error.code,
          'code',
          'database_schema_unsupported',
        ),
      ),
    );

    expect(
      sha256.convert(await File(fixture.sourcePath).readAsBytes()),
      before,
    );
    final database = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
    addTearDown(database.close);
    expect(await _pragmaInt(database, 'user_version'), 3);
    expect(await _tableNames(database), isNot(contains('schema_migrations')));
  });

  test('future schema is rejected without downgrading or mutation', () async {
    final fixture = await createLegacyDatabaseFixture(
      LegacyFixtureVersion.freshV4,
    );
    addTearDown(fixture.dispose);
    final raw = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
    await raw.execute('PRAGMA user_version = 9');
    await raw.close();
    final before = sha256.convert(await File(fixture.sourcePath).readAsBytes());

    await expectLater(
      _openManagedDatabase(fixture.sourcePath, DatabaseSchemaManager()),
      throwsA(
        isA<DatabaseSchemaException>().having(
          (error) => error.code,
          'code',
          'database_schema_unsupported',
        ),
      ),
    );

    expect(
      sha256.convert(await File(fixture.sourcePath).readAsBytes()),
      before,
    );
    final database = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
    addTearDown(database.close);
    expect(await _pragmaInt(database, 'user_version'), 9);
    expect(await _tableNames(database), isNot(contains('schema_migrations')));
  });
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

class _QuickCheckFailureDatabase implements Database {
  const _QuickCheckFailureDatabase(this._delegate);

  final Database _delegate;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return _delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    if (sql == 'PRAGMA quick_check') {
      return Future<List<Map<String, Object?>>>.value(
        const <Map<String, Object?>>[
          <String, Object?>{'quick_check': 'corrupt'},
        ],
      );
    }
    return _delegate.rawQuery(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
