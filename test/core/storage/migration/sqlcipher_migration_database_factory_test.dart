import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/migration/sqlcipher_migration_database_factory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'opens legacy and pending databases with isolated credentials',
    () async {
      final calls = <_OpenCall>[];
      final factory = SqlCipherMigrationDatabaseFactory(
        openDatabase:
            ({
              required path,
              required password,
              required readOnly,
              version,
              onCreate,
            }) async {
              calls.add(
                _OpenCall(
                  path: path,
                  password: password,
                  readOnly: readOnly,
                  version: version,
                  onCreate: onCreate,
                ),
              );
              return databaseFactoryFfi.openDatabase(
                inMemoryDatabasePath,
                options: OpenDatabaseOptions(singleInstance: false),
              );
            },
      );

      final legacy = await factory.openLegacy(
        path: 'legacy.db',
        password: 'legacy-password',
      );
      final pending = await factory.openPending(
        path: 'pending.db',
        password: 'new-password',
        version: 4,
        onCreate: (database, version) async {},
      );
      addTearDown(legacy.close);
      addTearDown(pending.close);

      expect(calls, hasLength(2));
      expect(calls[0].path, 'legacy.db');
      expect(calls[0].password, 'legacy-password');
      expect(calls[0].readOnly, isTrue);
      expect(calls[0].version, isNull);
      expect(calls[0].onCreate, isNull);
      expect(calls[1].path, 'pending.db');
      expect(calls[1].password, 'new-password');
      expect(calls[1].readOnly, isFalse);
      expect(calls[1].version, 4);
      expect(calls[1].onCreate, isNotNull);
    },
  );
}

class _OpenCall {
  const _OpenCall({
    required this.path,
    required this.password,
    required this.readOnly,
    required this.version,
    required this.onCreate,
  });

  final String path;
  final String password;
  final bool readOnly;
  final int? version;
  final OnDatabaseCreateFn? onCreate;
}
