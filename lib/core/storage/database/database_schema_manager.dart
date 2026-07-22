import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5_data_migration.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5_objects.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5_rebuild.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v6_migration.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v7_migration.dart';
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
  v7BaselineValidated,
  v7SchemaObjectsCreated,
  v7PostconditionsValidated,
  v7LedgerWritten,
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

  static const int latestVersion = 7;
  static const String v5MigrationName = 'database_schema_v5';
  static const String v5MigrationChecksum =
      '72961f4e65faded09a0b1afdfdadee2b'
      '3fb4cf0bb016a4519692adfdb0adeca8';
  static const String v5ExpectedFingerprint =
      '788a6b784f6c1e31db0382fa84c663a5'
      'dcd00e6a99dfc4913bb0ef551a311c0c';
  static const String v6MigrationName = 'database_schema_v6';
  static const String v6MigrationChecksum =
      'e91b4d4595beab7f2343439d177d28fa'
      '570300b27eb33de89f5f2447f1d14183';
  static const String v6ExpectedFingerprint =
      'cdcfbebdc3dff31920a81cb4e6890f12'
      '28fbdd4a18a226407e67a568d2e1ad41';
  static const String v7MigrationName = 'database_schema_v7';
  static const String v7MigrationChecksum =
      'e153245d83136f5423a8f9500fd2d492'
      'f4fb68b2e655b27c9267f38716be75b6';
  static const String migrationName = v7MigrationName;
  static const String migrationChecksum = v7MigrationChecksum;
  static const String expectedFingerprint =
      'c5e2ab18baf246a5e786d4689eb36e93'
      '9ca929d15644fd496a3f5daf5a6cbaeb';

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
    await _validateV6Baseline(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v6LedgerWritten);
    await _checkpoint(DatabaseMigrationCheckpoint.v7BaselineValidated);
    await DatabaseSchemaV7Migration.apply(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v7SchemaObjectsCreated);
    await DatabaseSchemaV7Migration.validatePostconditions(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v7PostconditionsValidated);
    await _writeLedger(
      database,
      version: 7,
      name: v7MigrationName,
      checksum: v7MigrationChecksum,
    );
    await _checkpoint(DatabaseMigrationCheckpoint.v7LedgerWritten);
    await _validateTargetStructure(database);
  }

  @override
  Future<void> upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if ((oldVersion != 4 && oldVersion != 5 && oldVersion != 6) ||
        newVersion != latestVersion) {
      throw const DatabaseSchemaException('database_schema_unsupported');
    }
    if (oldVersion == 4) {
      await _upgradeV4ToV5(database);
    } else if (oldVersion == 5) {
      await _validateV5Baseline(database);
    }
    if (oldVersion <= 5) {
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
      await _validateV6Baseline(database);
      await _checkpoint(DatabaseMigrationCheckpoint.v6LedgerWritten);
    } else {
      await _validateV6Baseline(database);
    }
    await _checkpoint(DatabaseMigrationCheckpoint.v7BaselineValidated);
    await DatabaseSchemaV7Migration.apply(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v7SchemaObjectsCreated);
    await DatabaseSchemaV7Migration.validatePostconditions(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v7PostconditionsValidated);
    await _writeLedger(
      database,
      version: 7,
      name: v7MigrationName,
      checksum: v7MigrationChecksum,
    );
    await _validateTargetStructure(database);
    await _checkpoint(DatabaseMigrationCheckpoint.v7LedgerWritten);
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

  Future<void> _validateLedgerThrough(
    DatabaseExecutor database,
    int throughVersion,
  ) async {
    final rows = await database.query(
      'schema_migrations',
      orderBy: 'version ASC',
    );
    final expected = <(int, String, String)>[
      (5, v5MigrationName, v5MigrationChecksum),
      (6, v6MigrationName, v6MigrationChecksum),
      (7, v7MigrationName, v7MigrationChecksum),
    ].where((entry) => entry.$1 <= throughVersion).toList(growable: false);
    if (rows.length != expected.length) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
    for (var index = 0; index < expected.length; index += 1) {
      final entry = expected[index];
      final row = rows[index];
      if (row['version'] != entry.$1 ||
          row['name'] != entry.$2 ||
          row['checksum'] != entry.$3) {
        throw const DatabaseSchemaException('database_schema_invalid');
      }
    }
  }

  Future<void> _validateTargetStructure(DatabaseExecutor database) async {
    await _validateIntegrity(database);
    await _validateLedgerThrough(database, latestVersion);
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

  Future<void> _validateIntegrity(DatabaseExecutor database) async {
    final quickCheck = await database.rawQuery('PRAGMA quick_check');
    if (quickCheck.length != 1 ||
        quickCheck.single.length != 1 ||
        quickCheck.single.values.single != 'ok' ||
        (await database.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
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
    await _validateLedgerThrough(database, 5);
    if (await fingerprint(database) != v5ExpectedFingerprint) {
      throw const DatabaseSchemaException('database_schema_invalid');
    }
  }

  Future<void> _validateV6Baseline(Database database) async {
    await _validateIntegrity(database);
    await _validateLedgerThrough(database, 6);
    if (await fingerprint(database) != v6ExpectedFingerprint) {
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
