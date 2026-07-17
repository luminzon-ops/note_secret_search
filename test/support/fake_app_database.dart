import 'dart:async';

import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class FakeAppDatabase implements AppDatabase {
  FakeAppDatabase({
    DatabaseLifecycleStatus initialStatus = DatabaseLifecycleStatus.locked,
  }) : _state = DatabaseLifecycleState(status: initialStatus);

  DatabaseLifecycleState _state;
  final StreamController<DatabaseLifecycleState> _states =
      StreamController<DatabaseLifecycleState>.broadcast(sync: true);

  @override
  DatabaseLifecycleState get state => _state;

  @override
  Stream<DatabaseLifecycleState> get states => _states.stream;

  @override
  Future<void> open(DatabaseSessionKeys sessionKeys) async {
    _emit(
      const DatabaseLifecycleState(status: DatabaseLifecycleStatus.opening),
    );
    _emit(const DatabaseLifecycleState(status: DatabaseLifecycleStatus.open));
  }

  void _emit(DatabaseLifecycleState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Future<T> run<T>(Future<T> Function(Database database) operation) {
    throw UnimplementedError('This fake does not expose a SQLite connection.');
  }

  @override
  Future<void> close() async {
    _emit(
      const DatabaseLifecycleState(status: DatabaseLifecycleStatus.closing),
    );
    _emit(const DatabaseLifecycleState.locked());
  }
}
