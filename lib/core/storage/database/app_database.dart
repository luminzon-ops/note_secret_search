import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
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
      4 => const <String>[DatabaseSchema.securityMetadataCreateStatement],
      _ => const <String>[],
    };
  }
}
