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
}
