import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

enum DatabaseLifecycleStatus { locked, opening, open, closing, error }

class DatabaseLifecycleState {
  const DatabaseLifecycleState({
    required this.status,
    this.openingStage,
    this.errorCode,
  });

  const DatabaseLifecycleState.locked()
    : status = DatabaseLifecycleStatus.locked,
      openingStage = null,
      errorCode = null;

  final DatabaseLifecycleStatus status;
  final String? openingStage;
  final String? errorCode;
}

class DatabaseAccessRevokedException implements Exception {
  const DatabaseAccessRevokedException();

  String get code => 'database_access_revoked';

  @override
  String toString() => code;
}

class DatabaseLifecycleException implements Exception {
  const DatabaseLifecycleException(this.code);

  final String code;

  @override
  String toString() => code;
}

abstract interface class AppDatabase {
  DatabaseLifecycleState get state;

  Stream<DatabaseLifecycleState> get states;

  Future<void> open(DatabaseSessionKeys sessionKeys);

  Future<T> run<T>(Future<T> Function(Database database) operation);

  Future<T> transaction<T>(
    Future<T> Function(DatabaseExecutor executor) operation,
  );

  Future<void> close();
}
