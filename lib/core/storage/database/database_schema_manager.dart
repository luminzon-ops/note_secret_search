import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5_data_migration.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5_objects.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5_rebuild.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v6_migration.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

abstract interface class DatabaseSchemaController {
  int get version;

  Future<void> configure(Database database);

  Future<void> create(Database database, int version);

  Future<void> upgrade(Database database, int oldVersion, int newVersion);

  Future<void> downgrade(Database database, int oldVersion, int newVersion);

  Future<void> validate(Database database);
}

class DatabaseSchemaException implements Exception {
  const DatabaseSchemaException(this.code);

  final String code;

  @override
  String toString() => code;
}

enum DatabaseMigrationCheckpoint {
  inventoryValidated,
  historicalDriftRepaired,
  dataNormalized,
  tablesRebuilt,
  schemaObjectsCreated,
  postconditionsValidated,
  ledgerWritten,
  v6BaselineValidated,
  v6SchemaObjectsCreated,
  v6PostconditionsValidated,
  v6LedgerWritten,
}

typedef DatabaseMigrationCheckpointCallback =
    Future<void> Function(DatabaseMigrationCheckpoint checkpoint);

class DatabaseSchemaManager implements DatabaseSchemaController {
  DatabaseSchemaManager({
    int Function()? nowMilliseconds,
    DatabaseMigrationCheckpointCallback? onMigrationCheckpoint,
  }) : _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch),
       _onMigrationCheckpoint = onMigrationCheckpoint;

  static const int latestVersion = 6;
  static const String v5MigrationName = 'database_schema_v5';
  static const String v5MigrationChecksum =
      '72961f4e65faded09a0b1afdfdadee2b'
      '3fb4cf0bb016a4519692adfdb0adeca8';
  static const String v5ExpectedFingerprint =
      '788a6b784f6c1e31db0382fa84c663a5'
      'dcd00e6a99dfc4913bb0ef551a311c0c';
  static const String v6MigrationName = 'database_schema_v6';
  static const String v6MigrationChecksum =
      'e4330eefceac703fc8436da05e40ad593875148782b3f7dea3fbe9c50f6bfb10';
  static const String migrationName = v6MigrationName;
  static const String migrationChecksum = v6MigrationChecksum;
  static const String expectedFingerprint =
      '29d431c6ea08e6de7236657a4aa370328070628ed337817e2de1afbbc67b455e';

  final int Function() _nowMilliseconds;
  final DatabaseMigrationCheckpointCallback? _onMigrationCheckpoint;

  @override
  int get version => latestVersion;

  @override
  Future<void> configure(Database database) {
    return database.execute('PRAGMA foreign_keys = ON');
  }

  @override
  Future<void> create(Database database, int version) async {
    if (version != latestVersion) {
      throw const DatabaseSchemaException('database_schema_unsupported');
    }
    final batch = database.batch();
    for (final statement in DatabaseSchemaV5.createStatements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
    await _ensureDefaultVault(database);
    await _writeLedger(
      database,
      version: 5,
      name: v5MigrationName,
      checksum: v5MigrationChecksum,
    );
    await DatabaseSchemaV6Migration.apply(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v6SchemaObjectsCreated);
    await DatabaseSchemaV6Migration.validateEmptyDerivedData(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v6PostconditionsValidated);
    await _writeLedger(
      database,
      version: 6,
      name: v6MigrationName,
      checksum: v6MigrationChecksum,
    );
    await _checkpoint(DatabaseMigrationCheckpoint.v6LedgerWritten);
    await _validateTargetStructure(database);
  }

  @override
  Future<void> upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if ((oldVersion != 4 && oldVersion != 5) || newVersion != latestVersion) {
      throw const DatabaseSchemaException('database_schema_unsupported');
    }
    if (oldVersion == 4) {
      await _upgradeV4ToV5(database);
    } else {
      await _validateV5Baseline(database);
    }
    await _checkpoint(DatabaseMigrationCheckpoint.v6BaselineValidated);
    await DatabaseSchemaV6Migration.apply(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v6SchemaObjectsCreated);
    await DatabaseSchemaV6Migration.validateEmptyDerivedData(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v6PostconditionsValidated);
    await database.execute(DatabaseSchemaV5.schemaMigrationsCreateStatement);
    await _writeLedger(
      database,
      version: 6,
      name: v6MigrationName,
      checksum: v6MigrationChecksum,
    );
    await _validateTargetStructure(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v6LedgerWritten);
  }

  @override
  Future<void> downgrade(Database database, int oldVersion, int newVersion) {
    throw const DatabaseSchemaException('database_schema_unsupported');
  }

  @override
  Future<void> validate(Database database) async {
    if (await _pragmaInt(database, 'user_version') != latestVersion ||
        await _pragmaInt(database, 'foreign_keys') != 1) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
    await _validateTargetStructure(database);
  }

  Future<String> fingerprint(DatabaseExecutor database) async {
    final inventory = <Object?>[];
    final tables = await database.rawQuery('''
      SELECT name, sql FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ORDER BY name
      ''');
    for (final tableRow in tables) {
      final table = tableRow['name']! as String;
      final columns = await database.rawQuery(
        'PRAGMA table_info(${_quoteIdentifier(table)})',
      );
      final canonicalColumns =
          columns
              .map(
                (row) => <Object?>[
                  row['name'],
                  row['type'].toString().toUpperCase(),
                  row['notnull'],
                  row['dflt_value']?.toString(),
                  row['pk'],
                ],
              )
              .toList()
            ..sort(
              (left, right) =>
                  (left[0]! as String).compareTo(right[0]! as String),
            );
      final foreignKeys = await database.rawQuery(
        'PRAGMA foreign_key_list(${_quoteIdentifier(table)})',
      );
      final canonicalForeignKeys =
          foreignKeys
              .map(
                (row) => <Object?>[
                  row['id'],
                  row['seq'],
                  row['table'],
                  row['from'],
                  row['to'],
                  row['on_update'],
                  row['on_delete'],
                  row['match'],
                ],
              )
              .toList()
            ..sort(_compareCanonicalRows);
      inventory.add(<Object?>[
        'table',
        table,
        canonicalColumns,
        canonicalForeignKeys,
        _normalizeSql(tableRow['sql']?.toString()),
      ]);
    }

    final objects = await database.rawQuery('''
      SELECT type, name, tbl_name, sql FROM sqlite_master
      WHERE type IN ('index', 'trigger') AND name NOT LIKE 'sqlite_%'
      ORDER BY type, name
      ''');
    for (final row in objects) {
      final type = row['type']! as String;
      final name = row['name']! as String;
      final columns = type == 'index'
          ? (await database.rawQuery(
              'PRAGMA index_info(${_quoteIdentifier(name)})',
            )).map((column) => column['name']).toList(growable: false)
          : const <Object?>[];
      inventory.add(<Object?>[
        type,
        name,
        row['tbl_name'],
        columns,
        _normalizeSql(row['sql']?.toString()),
      ]);
    }
    return sha256.convert(utf8.encode(jsonEncode(inventory))).toString();
  }

  Future<void> _ensureDefaultVault(DatabaseExecutor database) async {
    final vaults = await database.query(
      'vaults',
      columns: const <String>['id', 'is_default'],
      orderBy: 'created_at ASC, id ASC',
    );
    if (vaults.isNotEmpty) {
      if (vaults.where((row) => row['is_default'] == 1).length != 1) {
        throw const DatabaseSchemaException('database_schema_invalid');
      }
      return;
    }
    final now = _nowMilliseconds();
    await database.insert('vaults', <String, Object?>{
      'id': 'default',
      'name': '默认保险库',
      'description': '首版默认保险库',
      'is_default': 1,
      'encryption_version': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> _writeLedger(
    DatabaseExecutor database, {
    required int version,
    required String name,
    required String checksum,
  }) {
    return database.insert('schema_migrations', <String, Object?>{
      'version': version,
      'name': name,
      'checksum': checksum,
      'applied_at': _nowMilliseconds(),
    });
  }

  Future<void> _validateLedger(DatabaseExecutor database) async {
    final rows = await database.query(
      'schema_migrations',
      orderBy: 'version ASC',
    );
    if (rows.length != 2 ||
        rows[0]['version'] != 5 ||
        rows[0]['name'] != v5MigrationName ||
        rows[0]['checksum'] != v5MigrationChecksum ||
        rows[1]['version'] != 6 ||
        rows[1]['name'] != v6MigrationName ||
        rows[1]['checksum'] != v6MigrationChecksum) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
  }

  Future<void> _validateTargetStructure(DatabaseExecutor database) async {
    await _validateLedger(database);
    final defaults = await database.rawQuery('''
      SELECT COUNT(*) AS count
      FROM vaults
      WHERE is_default = 1
      ''');
    if (defaults.single['count'] != 1) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
    if (await fingerprint(database) != expectedFingerprint) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
  }

  Future<void> _validateRebuildPostconditions(DatabaseExecutor database) async {
    try {
      await DatabaseSchemaV5Rebuild.validatePostconditions(database);
    } on DatabaseSchemaV5RebuildException {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
  }

  Future<void> _upgradeV4ToV5(Database database) async {
    try {
      await DatabaseSchemaV5Rebuild.validateV4Inventory(database);
    } on DatabaseSchemaV5RebuildException {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
    await _checkpoint(DatabaseMigrationCheckpoint.inventoryValidated);
    final modelColumns = {
      for (final row in await database.rawQuery(
        'PRAGMA table_info(model_registry)',
      ))
        row['name']! as String,
    };
    if (!modelColumns.contains('integrity_status')) {
      await database.execute('''
        ALTER TABLE model_registry ADD COLUMN integrity_status
        TEXT NOT NULL DEFAULT 'unknown'
        ''');
    }
    await _checkpoint(DatabaseMigrationCheckpoint.historicalDriftRepaired);
    try {
      await DatabaseSchemaV5DataMigration.normalize(
        database,
        nowMilliseconds: _nowMilliseconds,
      );
    } on DatabaseSchemaV5DataMigrationException {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
    await _checkpoint(DatabaseMigrationCheckpoint.dataNormalized);
    try {
      await DatabaseSchemaV5Rebuild.rebuildTables(database);
    } on DatabaseSchemaV5RebuildException {
      throw const DatabaseSchemaException('database_schema_invalid');
    } on DatabaseException {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
    await _checkpoint(DatabaseMigrationCheckpoint.tablesRebuilt);
    try {
      for (final statement in DatabaseSchemaV5Objects.createStatements) {
        await database.execute(statement);
      }
    } on DatabaseException {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
    await _checkpoint(DatabaseMigrationCheckpoint.schemaObjectsCreated);
    await _validateRebuildPostconditions(database);
    await _checkpoint(DatabaseMigrationCheckpoint.postconditionsValidated);
    await database.execute(DatabaseSchemaV5.schemaMigrationsCreateStatement);
    await _writeLedger(
      database,
      version: 5,
      name: v5MigrationName,
      checksum: v5MigrationChecksum,
    );
    if (await fingerprint(database) != v5ExpectedFingerprint) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
    await _checkpoint(DatabaseMigrationCheckpoint.ledgerWritten);
  }

  Future<void> _validateV5Baseline(Database database) async {
    await _validateLedgerV5Only(database);
    if (await fingerprint(database) != v5ExpectedFingerprint) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
  }

  Future<void> _validateLedgerV5Only(DatabaseExecutor database) async {
    final rows = await database.query('schema_migrations');
    if (rows.length != 1 ||
        rows.single['version'] != 5 ||
        rows.single['name'] != v5MigrationName ||
        rows.single['checksum'] != v5MigrationChecksum) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
  }

  Future<void> _checkpoint(DatabaseMigrationCheckpoint checkpoint) async {
    await _onMigrationCheckpoint?.call(checkpoint);
  }
}

Future<int> _pragmaInt(DatabaseExecutor database, String pragma) async {
  final row = (await database.rawQuery('PRAGMA $pragma')).single;
  return row.values.single as int;
}

int _compareCanonicalRows(List<Object?> left, List<Object?> right) {
  return jsonEncode(left).compareTo(jsonEncode(right));
}

String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

String? _normalizeSql(String? value) {
  return value?.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
