import 'package:note_secret_search/core/storage/database/database_schema_v4_inventory.dart';
import 'package:note_secret_search/core/storage/database/database_schema_v5.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

class DatabaseSchemaV5RebuildException implements Exception {
  const DatabaseSchemaV5RebuildException();
}

abstract final class DatabaseSchemaV5Rebuild {
  static const String shadowPrefix = '__v4_';

  static Future<void> validateV4Inventory(DatabaseExecutor database) async {
    try {
      await DatabaseSchemaV4Inventory.validate(database);
    } on DatabaseSchemaV4InventoryException {
      throw const DatabaseSchemaV5RebuildException();
    }
  }

  static Future<void> rebuildTables(DatabaseExecutor database) async {
    for (final table in DatabaseSchemaV5.businessTableNames) {
      await database.execute(
        'ALTER TABLE ${_quoteIdentifier(table)} '
        'RENAME TO ${_quoteIdentifier('$shadowPrefix$table')}',
      );
    }
    for (final statement in DatabaseSchemaV5.businessTableCreateStatements) {
      await database.execute(statement);
    }
    for (final table in _copyOrder) {
      final columns = DatabaseSchemaV4Inventory.tableColumns[table]!;
      final columnList = columns.map(_quoteIdentifier).join(', ');
      await database.execute(
        'INSERT INTO ${_quoteIdentifier(table)} ($columnList) '
        'SELECT $columnList '
        'FROM ${_quoteIdentifier('$shadowPrefix$table')}',
      );
    }
    for (final table in DatabaseSchemaV5.businessTableNames.reversed) {
      await database.execute(
        'DROP TABLE ${_quoteIdentifier('$shadowPrefix$table')}',
      );
    }
  }

  static Future<void> validatePostconditions(DatabaseExecutor database) async {
    final quickCheck = await database.rawQuery('PRAGMA quick_check');
    if (quickCheck.length != 1 || quickCheck.single.values.single != 'ok') {
      throw const DatabaseSchemaV5RebuildException();
    }
    if ((await database.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const DatabaseSchemaV5RebuildException();
    }
    final defaultCount = await database.rawQuery('''
      SELECT COUNT(*) AS count
      FROM vaults
      WHERE is_default = 1
      ''');
    if (defaultCount.single['count'] != 1) {
      throw const DatabaseSchemaV5RebuildException();
    }
    final embeddings = await database.rawQuery(
      'SELECT 1 FROM embedding_chunks LIMIT 1',
    );
    if (embeddings.isNotEmpty) {
      throw const DatabaseSchemaV5RebuildException();
    }
    final shadows = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE name LIKE '$shadowPrefix%' LIMIT 1",
    );
    if (shadows.isNotEmpty) {
      throw const DatabaseSchemaV5RebuildException();
    }
  }
}

const _copyOrder = <String>[
  'vaults',
  'categories',
  'secret_items',
  'note_items',
  'tags',
  'item_tags',
  'model_registry',
  'embedding_chunks',
  'model_catalog_entries',
  'download_tasks',
  'provider_configs',
  'sync_accounts',
  'app_settings',
  'chat_sessions',
  'chat_messages',
  'security_metadata',
];

String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';
