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

  test('fresh database creates and validates schema v5', () async {
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

    expect(await _pragmaInt(database, 'user_version'), 5);
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
    expect(await database.query('schema_migrations'), <Map<String, Object?>>[
      <String, Object?>{
        'version': 5,
        'name': DatabaseSchemaManager.migrationName,
        'checksum': DatabaseSchemaManager.migrationChecksum,
        'applied_at': 1_800_000_000_000,
      },
    ]);
    expect(
      await manager.fingerprint(database),
      DatabaseSchemaManager.expectedFingerprint,
    );
  });

  test('upgraded v4 adds missing integrity column without data loss', () async {
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

    expect(await _pragmaInt(database, 'user_version'), 5);
    final model = (await database.query('model_registry')).single;
    expect(model['id'], 'model-1');
    expect(model['integrity_status'], 'unknown');
    expect(model['artifact_paths_json'], '["/models/legacy.onnx"]');
    final secret = (await database.query(
      'secret_items',
      where: 'id = ?',
      whereArgs: const <Object>['secret-1'],
    )).single;
    expect(secret['title'], 'Primary account');
    expect(secret['username_ciphertext'], utf8.encode('alice'));
    expect(await database.query('schema_migrations'), hasLength(1));
    expect(
      await manager.fingerprint(database),
      DatabaseSchemaManager.expectedFingerprint,
    );
  });

  test('reopening v5 validates without repeating bootstrap writes', () async {
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

  test('v5 rejects a mismatched migration ledger without mutation', () async {
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
    await database.update('schema_migrations', <String, Object?>{
      'checksum': 'tampered',
    });

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
      (await database.query('schema_migrations')).single['checksum'],
      'tampered',
    );
  });

  test('v5 rejects a mismatched schema fingerprint without repair', () async {
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
    await raw.execute('PRAGMA user_version = 6');
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
    expect(await _pragmaInt(database, 'user_version'), 6);
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
