import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;
import 'package:sqflite_sqlcipher/sqlite_api.dart';

typedef SqlCipherMigrationDatabaseOpener =
    Future<Database> Function({
      required String path,
      required String password,
      required bool readOnly,
      int? version,
      OnDatabaseCreateFn? onCreate,
    });

class SqlCipherMigrationDatabaseFactory implements MigrationDatabaseFactory {
  const SqlCipherMigrationDatabaseFactory({
    SqlCipherMigrationDatabaseOpener openDatabase =
        _openSqlCipherMigrationDatabase,
  }) : _openDatabase = openDatabase;

  final SqlCipherMigrationDatabaseOpener _openDatabase;

  @override
  Future<Database> openLegacy({
    required String path,
    required String password,
  }) {
    return _openDatabase(path: path, password: password, readOnly: true);
  }

  @override
  Future<Database> openPending({
    required String path,
    required String password,
    required int version,
    required OnDatabaseCreateFn onCreate,
  }) {
    return _openDatabase(
      path: path,
      password: password,
      readOnly: false,
      version: version,
      onCreate: onCreate,
    );
  }
}

Future<Database> _openSqlCipherMigrationDatabase({
  required String path,
  required String password,
  required bool readOnly,
  int? version,
  OnDatabaseCreateFn? onCreate,
}) {
  return sqlcipher.openDatabase(
    path,
    password: password,
    readOnly: readOnly,
    singleInstance: false,
    version: version,
    onCreate: onCreate,
  );
}
