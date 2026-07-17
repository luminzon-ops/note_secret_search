import 'package:note_secret_search/core/security/database_session_keys.dart';
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
  DatabaseLifecycleState _state = const DatabaseLifecycleState(
    status: DatabaseLifecycleStatus.open,
  );

  @override
  DatabaseLifecycleState get state => _state;

  @override
  Stream<DatabaseLifecycleState> get states => const Stream.empty();

  @override
  Future<void> open(DatabaseSessionKeys sessionKeys) async {
    if (_state.status != DatabaseLifecycleStatus.open) {
      throw const DatabaseLifecycleException('database_invalid_transition');
    }
  }

  @override
  Future<T> run<T>(Future<T> Function(Database database) operation) async {
    if (_state.status != DatabaseLifecycleStatus.open) {
      throw const DatabaseAccessRevokedException();
    }
    return operation(_database);
  }

  @override
  Future<void> close() async {
    if (_state.status == DatabaseLifecycleStatus.locked) {
      return;
    }
    _state = const DatabaseLifecycleState(
      status: DatabaseLifecycleStatus.closing,
    );
    await _database.close();
    _state = const DatabaseLifecycleState.locked();
  }
}
