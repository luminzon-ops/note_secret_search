import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<TestAppDatabase> openTestAppDatabase() async {
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  for (final statement in DatabaseSchema.createStatements) {
    await database.execute(statement);
  }
  return TestAppDatabase(database);
}

class TestAppDatabase implements AppDatabase {
  TestAppDatabase(this._database);

  final Database _database;

  @override
  Future<Database> get database async => _database;

  @override
  Future<void> close() => _database.close();

  @override
  Future<void> ensureDefaultVault() async {}

  @override
  Future<void> executeBatch(List<String> statements) async {
    for (final statement in statements) {
      await _database.execute(statement);
    }
  }

  @override
  Future<void> initialize() async {}
}
