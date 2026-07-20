import 'package:note_secret_search/core/storage/database/database_schema_v6.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

abstract final class DatabaseSchemaV6Migration {
  static Future<void> apply(DatabaseExecutor database) async {
    await database.execute('DROP TABLE IF EXISTS embedding_chunks');
    for (final statement in DatabaseSchemaV6.createStatements) {
      await database.execute(statement);
    }
  }

  static Future<void> validateEmptyDerivedData(
    DatabaseExecutor database,
  ) async {
    if ((await database.query('embedding_index_sets')).isNotEmpty ||
        (await database.query('embedding_chunks')).isNotEmpty) {
      throw const DatabaseSchemaV6MigrationException();
    }
    final temporary = await database.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE name LIKE '__v6_%'
    ''');
    if (temporary.isNotEmpty) {
      throw const DatabaseSchemaV6MigrationException();
    }
  }
}

class DatabaseSchemaV6MigrationException implements Exception {
  const DatabaseSchemaV6MigrationException();
}
