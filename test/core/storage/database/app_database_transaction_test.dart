import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlcipher_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'close during a transaction revokes the result and rolls back writes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'note_secret_search_transaction_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = _createDatabase(directory.path);
      final keys = _sessionKeys();
      addTearDown(keys.clear);
      await database.open(keys);

      final operationStarted = Completer<void>();
      final releaseOperation = Completer<void>();
      final transaction = database.transaction<void>((executor) async {
        await executor.update(
          DatabaseSchema.vaults,
          const <String, Object?>{'name': 'mutated'},
          where: 'id = ?',
          whereArgs: const <Object>['default'],
        );
        operationStarted.complete();
        await releaseOperation.future;
      });
      await operationStarted.future;

      final closing = database.close();
      final transactionExpectation = expectLater(
        transaction,
        throwsA(isA<DatabaseAccessRevokedException>()),
      );
      releaseOperation.complete();
      await transactionExpectation;
      await closing;

      final reopened = await databaseFactoryFfi.openDatabase(
        p.join(directory.path, 'note_secret_search.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(reopened.close);
      final vault = (await reopened.query(
        DatabaseSchema.vaults,
        where: 'id = ?',
        whereArgs: const <Object>['default'],
      )).single;
      expect(vault['name'], isNot('mutated'));
    },
  );

  test('successful transactions commit their writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'note_secret_search_transaction_commit_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = _createDatabase(directory.path);
    final keys = _sessionKeys();
    addTearDown(() async {
      await database.close();
      keys.clear();
    });
    await database.open(keys);

    await database.transaction<void>((executor) {
      return executor.update(
        DatabaseSchema.vaults,
        const <String, Object?>{'name': 'committed'},
        where: 'id = ?',
        whereArgs: const <Object>['default'],
      );
    });

    final name = await database.run<Object?>((executor) async {
      final vault = (await executor.query(
        DatabaseSchema.vaults,
        columns: const <String>['name'],
        where: 'id = ?',
        whereArgs: const <Object>['default'],
      )).single;
      return vault['name'];
    });
    expect(name, 'committed');
  });

  test(
    'operation failures roll back and preserve the original error',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'note_secret_search_transaction_rollback_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = _createDatabase(directory.path);
      final keys = _sessionKeys();
      addTearDown(() async {
        await database.close();
        keys.clear();
      });
      await database.open(keys);

      await expectLater(
        database.transaction<void>((executor) async {
          await executor.update(
            DatabaseSchema.vaults,
            const <String, Object?>{'name': 'rolled-back'},
            where: 'id = ?',
            whereArgs: const <Object>['default'],
          );
          throw StateError('sentinel_transaction_failure');
        }),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'sentinel_transaction_failure',
          ),
        ),
      );

      final name = await database.run<Object?>((executor) async {
        final vault = (await executor.query(
          DatabaseSchema.vaults,
          columns: const <String>['name'],
          where: 'id = ?',
          whereArgs: const <Object>['default'],
        )).single;
        return vault['name'];
      });
      expect(name, isNot('rolled-back'));
    },
  );

  test('locked databases reject transactions before opening a connection', () {
    final database = _createDatabase('unused');

    return expectLater(
      database.transaction<void>((_) async {}),
      throwsA(isA<DatabaseAccessRevokedException>()),
    );
  });
}

SqlCipherAppDatabase _createDatabase(String directoryPath) {
  return SqlCipherAppDatabase(
    logger: const AppLogger(),
    databasePathProvider: () async => directoryPath,
    openConnection:
        ({
          required path,
          required password,
          required version,
          required onConfigure,
          required onCreate,
          required onUpgrade,
          required onDowngrade,
        }) {
          return databaseFactoryFfi.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: version,
              onConfigure: onConfigure,
              onCreate: onCreate,
              onUpgrade: onUpgrade,
              onDowngrade: onDowngrade,
              singleInstance: false,
            ),
          );
        },
  );
}

DatabaseSessionKeys _sessionKeys() {
  return DatabaseSessionKeys(
    databaseKey: Uint8List.fromList(List<int>.generate(32, (index) => index)),
    fieldKey: Uint8List.fromList(List<int>.filled(32, 0x7f)),
  );
}
