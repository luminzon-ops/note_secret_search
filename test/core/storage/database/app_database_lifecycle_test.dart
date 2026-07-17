import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlcipher_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'starts locked and rejects database work before authentication',
    () async {
      var openerCalled = false;
      final database = SqlCipherAppDatabase(
        logger: const AppLogger(),
        databasePathProvider: () async => 'unused.db',
        openConnection:
            ({
              required path,
              required password,
              required version,
              required onCreate,
              required onUpgrade,
            }) async {
              openerCalled = true;
              throw StateError('must not open');
            },
      );

      expect(database.state.status, DatabaseLifecycleStatus.locked);
      await expectLater(
        database.run<void>((_) async {}),
        throwsA(
          isA<DatabaseAccessRevokedException>().having(
            (error) => error.code,
            'code',
            'database_access_revoked',
          ),
        ),
      );
      expect(openerCalled, isFalse);
    },
  );

  test('opens with the session database key before publishing open', () async {
    final observedStatuses = <DatabaseLifecycleStatus>[];
    String? openedPassword;
    late SqlCipherAppDatabase database;
    database = SqlCipherAppDatabase(
      logger: const AppLogger(),
      databasePathProvider: () async => 'unused',
      openConnection:
          ({
            required path,
            required password,
            required version,
            required onCreate,
            required onUpgrade,
          }) async {
            expect(database.state.status, DatabaseLifecycleStatus.opening);
            openedPassword = password;
            return databaseFactoryFfi.openDatabase(
              inMemoryDatabasePath,
              options: OpenDatabaseOptions(
                version: version,
                onCreate: onCreate,
                onUpgrade: onUpgrade,
              ),
            );
          },
    );
    final subscription = database.states.listen(
      (state) => observedStatuses.add(state.status),
    );
    final keys = _sessionKeys();
    addTearDown(() async {
      await subscription.cancel();
      await database.close();
      keys.clear();
    });

    await database.open(keys);

    expect(openedPassword, _databaseKeyHex);
    expect(observedStatuses, <DatabaseLifecycleStatus>[
      DatabaseLifecycleStatus.opening,
      DatabaseLifecycleStatus.open,
    ]);
    expect(database.state.status, DatabaseLifecycleStatus.open);
    final vaultCount = await database.run<int>((connection) async {
      final rows = await connection.query(
        DatabaseSchema.vaults,
        where: 'id = ?',
        whereArgs: const <Object?>['default'],
      );
      return rows.length;
    });
    expect(vaultCount, 1);
  });

  test('sanitizes connection failures and publishes error state', () async {
    final keys = _sessionKeys();
    addTearDown(keys.clear);
    final database = SqlCipherAppDatabase(
      logger: const AppLogger(),
      databasePathProvider: () async => 'unused',
      openConnection:
          ({
            required path,
            required password,
            required version,
            required onCreate,
            required onUpgrade,
          }) async {
            throw StateError('SENTINEL_DATABASE_PATH');
          },
    );

    await expectLater(
      database.open(keys),
      throwsA(
        isA<DatabaseLifecycleException>()
            .having((error) => error.code, 'code', 'database_open_failed')
            .having(
              (error) => error.toString(),
              'sanitized message',
              isNot(contains('SENTINEL_DATABASE_PATH')),
            ),
      ),
    );

    expect(database.state.status, DatabaseLifecycleStatus.error);
    expect(database.state.errorCode, 'database_open_failed');
  });

  test('close immediately revokes new and stale database work', () async {
    final keys = _sessionKeys();
    final database = SqlCipherAppDatabase(
      logger: const AppLogger(),
      databasePathProvider: () async => 'unused',
      openConnection:
          ({
            required path,
            required password,
            required version,
            required onCreate,
            required onUpgrade,
          }) {
            return databaseFactoryFfi.openDatabase(
              inMemoryDatabasePath,
              options: OpenDatabaseOptions(
                version: version,
                onCreate: onCreate,
                onUpgrade: onUpgrade,
              ),
            );
          },
    );
    addTearDown(keys.clear);
    await database.open(keys);
    final operationStarted = Completer<void>();
    final releaseOperation = Completer<void>();
    final staleResult = database.run<String>((_) async {
      operationStarted.complete();
      await releaseOperation.future;
      return 'must not escape';
    });
    await operationStarted.future;

    final closing = database.close();

    expect(database.state.status, DatabaseLifecycleStatus.closing);
    await expectLater(
      database.run<void>((_) async {}),
      throwsA(isA<DatabaseAccessRevokedException>()),
    );
    final staleExpectation = expectLater(
      staleResult,
      throwsA(isA<DatabaseAccessRevokedException>()),
    );
    releaseOperation.complete();
    await closing;
    await staleExpectation;
    expect(database.state.status, DatabaseLifecycleStatus.locked);
  });

  test('close during open never publishes the late connection', () async {
    final keys = _sessionKeys();
    final openerStarted = Completer<void>();
    final releaseOpener = Completer<void>();
    final statuses = <DatabaseLifecycleStatus>[];
    final database = SqlCipherAppDatabase(
      logger: const AppLogger(),
      databasePathProvider: () async => 'unused',
      openConnection:
          ({
            required path,
            required password,
            required version,
            required onCreate,
            required onUpgrade,
          }) async {
            openerStarted.complete();
            await releaseOpener.future;
            return databaseFactoryFfi.openDatabase(
              inMemoryDatabasePath,
              options: OpenDatabaseOptions(
                version: version,
                onCreate: onCreate,
                onUpgrade: onUpgrade,
              ),
            );
          },
    );
    final subscription = database.states.listen(
      (state) => statuses.add(state.status),
    );
    addTearDown(() async {
      await subscription.cancel();
      keys.clear();
    });

    final opening = database.open(keys);
    final openingExpectation = expectLater(
      opening,
      throwsA(isA<DatabaseAccessRevokedException>()),
    );
    await openerStarted.future;
    var closeCompleted = false;
    final closing = database.close().whenComplete(() {
      closeCompleted = true;
    });

    expect(database.state.status, DatabaseLifecycleStatus.closing);
    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);
    releaseOpener.complete();
    await openingExpectation;
    await closing;

    expect(database.state.status, DatabaseLifecycleStatus.locked);
    expect(statuses, isNot(contains(DatabaseLifecycleStatus.open)));
  });

  test(
    'close timeout still closes and rejects the late lease result',
    () async {
      final keys = _sessionKeys();
      final database = SqlCipherAppDatabase(
        logger: const AppLogger(),
        closeTimeout: const Duration(milliseconds: 20),
        databasePathProvider: () async => 'unused',
        openConnection:
            ({
              required path,
              required password,
              required version,
              required onCreate,
              required onUpgrade,
            }) {
              return databaseFactoryFfi.openDatabase(
                inMemoryDatabasePath,
                options: OpenDatabaseOptions(
                  version: version,
                  onCreate: onCreate,
                  onUpgrade: onUpgrade,
                ),
              );
            },
      );
      addTearDown(keys.clear);
      await database.open(keys);
      final operationStarted = Completer<void>();
      final releaseOperation = Completer<void>();
      final lateResult = database.run<void>((_) async {
        operationStarted.complete();
        await releaseOperation.future;
      });
      final lateExpectation = expectLater(
        lateResult,
        throwsA(isA<DatabaseAccessRevokedException>()),
      );
      await operationStarted.future;

      await database.close();

      expect(database.state.status, DatabaseLifecycleStatus.locked);
      releaseOperation.complete();
      await lateExpectation;
    },
  );

  test('close failure remains revoked and can be retried', () async {
    final keys = _sessionKeys();
    final connection = _CloseControlledDatabase(failuresBeforeSuccess: 1);
    final database = SqlCipherAppDatabase(
      logger: const AppLogger(),
      databasePathProvider: () async => 'unused',
      openConnection:
          ({
            required path,
            required password,
            required version,
            required onCreate,
            required onUpgrade,
          }) async {
            return connection;
          },
    );
    addTearDown(keys.clear);
    await database.open(keys);

    await expectLater(
      database.close(),
      throwsA(
        isA<DatabaseLifecycleException>()
            .having((error) => error.code, 'code', 'database_close_failed')
            .having(
              (error) => error.toString(),
              'sanitized message',
              isNot(contains('SENTINEL_CLOSE_FAILURE')),
            ),
      ),
    );

    expect(database.state.status, DatabaseLifecycleStatus.error);
    await expectLater(
      database.run<void>((_) async {}),
      throwsA(isA<DatabaseAccessRevokedException>()),
    );
    await database.close();
    expect(connection.closeCalls, 2);
    expect(database.state.status, DatabaseLifecycleStatus.locked);
  });
}

const _databaseKeyHex =
    '000102030405060708090a0b0c0d0e0f'
    '101112131415161718191a1b1c1d1e1f';

DatabaseSessionKeys _sessionKeys() {
  return DatabaseSessionKeys(
    databaseKey: Uint8List.fromList(List<int>.generate(32, (index) => index)),
    fieldKey: Uint8List.fromList(List<int>.filled(32, 0x7f)),
  );
}

class _CloseControlledDatabase implements Database {
  _CloseControlledDatabase({required this.failuresBeforeSuccess});

  final int failuresBeforeSuccess;
  int closeCalls = 0;
  bool _isOpen = true;

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    return 1;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (closeCalls <= failuresBeforeSuccess) {
      throw StateError('SENTINEL_CLOSE_FAILURE');
    }
    _isOpen = false;
  }

  @override
  bool get isOpen => _isOpen;

  @override
  String get path => 'controlled.db';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
