import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

abstract interface class AppDatabase {
  Future<void> initialize();

  Future<void> executeBatch(List<String> statements);

  Future<Database> get database;

  Future<void> ensureDefaultVault();

  Future<void> close();
}

abstract final class DatabaseMigrations {
  static List<String> initial() => DatabaseSchema.createStatements;

  static List<String> forVersion(int version) {
    return switch (version) {
      2 => DatabaseSchema.chatPersistenceStatements,
      3 => const <String>[
          'ALTER TABLE model_registry ADD COLUMN artifact_paths_json TEXT',
        ],
      _ => const <String>[],
    };
  }
}
