import 'package:note_secret_search/core/storage/database/database_schema_v7.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

abstract final class DatabaseSchemaV7Migration {
  static Future<void> apply(DatabaseExecutor database) async {
    final columns = {
      for (final row in await database.rawQuery(
        'PRAGMA table_info(chat_messages)',
      ))
        row['name']! as String,
    };
    for (final entry in DatabaseSchemaV7.provenanceColumnStatements.entries) {
      if (!columns.contains(entry.key)) {
        await database.execute(entry.value);
      }
    }
    await database.execute(DatabaseSchemaV7.disableProviderConfigsStatement);
    await database.execute(DatabaseSchemaV7.dropProviderEnabledIndexStatement);
    await database.execute(
      DatabaseSchemaV7.createProviderEnabledIndexStatement,
    );
  }

  static Future<void> validatePostconditions(DatabaseExecutor database) async {
    final columns = {
      for (final row in await database.rawQuery(
        'PRAGMA table_info(chat_messages)',
      ))
        row['name']! as String,
    };
    if (!columns.containsAll(
      DatabaseSchemaV7.provenanceColumnStatements.keys,
    )) {
      throw const DatabaseSchemaV7MigrationException();
    }
    final enabledProviders = await database.rawQuery('''
      SELECT COUNT(*) AS count
      FROM provider_configs
      WHERE enabled <> 0
      ''');
    if (enabledProviders.single['count'] != 0) {
      throw const DatabaseSchemaV7MigrationException();
    }
    final provenance = await database.rawQuery('''
      SELECT id
      FROM chat_messages
      WHERE actual_backend IS NOT NULL
        OR actual_model IS NOT NULL
        OR provider_fingerprint IS NOT NULL
      LIMIT 1
      ''');
    if (provenance.isNotEmpty) {
      throw const DatabaseSchemaV7MigrationException();
    }
    final temporary = await database.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE name LIKE '__v7_%'
      ''');
    if (temporary.isNotEmpty) {
      throw const DatabaseSchemaV7MigrationException();
    }
  }
}

class DatabaseSchemaV7MigrationException implements Exception {
  const DatabaseSchemaV7MigrationException();
}
