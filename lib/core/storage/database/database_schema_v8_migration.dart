import 'package:note_secret_search/core/storage/database/database_schema_v8.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

abstract final class DatabaseSchemaV8Migration {
  static Future<void> apply(DatabaseExecutor database) async {
    await database.execute(DatabaseSchemaV8.catalogStateCreateStatement);
    await database.execute(DatabaseSchemaV8.registryArtifactsCreateStatement);
    await database.execute(DatabaseSchemaV8.installJournalCreateStatement);

    final columns = {
      for (final row in await database.rawQuery(
        'PRAGMA table_info(download_tasks)',
      ))
        row['name']! as String,
    };
    var receivedBytesAdded = false;
    for (final entry in DatabaseSchemaV8.downloadTaskColumnStatements.entries) {
      if (columns.contains(entry.key)) {
        continue;
      }
      await database.execute(entry.value);
      if (entry.key == 'received_bytes') {
        receivedBytesAdded = true;
      }
    }
    if (receivedBytesAdded) {
      await database.execute(DatabaseSchemaV8.backfillReceivedBytesStatement);
    }

    await database.execute(
      DatabaseSchemaV8.createRegistryArtifactsModelIndexStatement,
    );
    await database.execute(
      DatabaseSchemaV8.createDownloadIdentityIndexStatement,
    );
    await database.execute(
      DatabaseSchemaV8.createDownloadOperationIndexStatement,
    );
    await database.execute(
      DatabaseSchemaV8.createInstallJournalModelIndexStatement,
    );
  }

  static Future<void> validatePostconditions(DatabaseExecutor database) async {
    final tables = {
      for (final row in await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name']! as String,
    };
    if (!tables.containsAll(<String>{
      DatabaseSchemaV8.catalogStateTable,
      DatabaseSchemaV8.registryArtifactsTable,
      DatabaseSchemaV8.installJournalTable,
    })) {
      throw const DatabaseSchemaV8MigrationException();
    }

    final columns = {
      for (final row in await database.rawQuery(
        'PRAGMA table_info(download_tasks)',
      ))
        row['name']! as String,
    };
    if (!columns.containsAll(
      DatabaseSchemaV8.downloadTaskColumnStatements.keys,
    )) {
      throw const DatabaseSchemaV8MigrationException();
    }

    final indexes = {
      for (final row in await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      ))
        row['name']! as String,
    };
    if (!indexes.containsAll(<String>{
      'idx_model_registry_artifacts_model_release',
      'uq_download_tasks_identity',
      'idx_download_tasks_operation_checkpoint',
      'idx_model_install_journal_model_phase',
    })) {
      throw const DatabaseSchemaV8MigrationException();
    }

    final temporary = await database.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE name LIKE '__v8_%'
    ''');
    if (temporary.isNotEmpty) {
      throw const DatabaseSchemaV8MigrationException();
    }
  }
}

class DatabaseSchemaV8MigrationException implements Exception {
  const DatabaseSchemaV8MigrationException();
}
