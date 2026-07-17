import 'dart:async';

import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

typedef DatabasePathProvider = Future<String> Function();
typedef SqlCipherDatabaseOpener =
    Future<Database> Function({
      required String path,
      required String password,
      required int version,
      required OnDatabaseCreateFn onCreate,
      required OnDatabaseVersionChangeFn onUpgrade,
    });

class SqlCipherAppDatabase implements AppDatabase {
  SqlCipherAppDatabase({
    required AppLogger logger,
    DatabasePathProvider? databasePathProvider,
    SqlCipherDatabaseOpener? openConnection,
    Duration closeTimeout = const Duration(seconds: 5),
  }) : _logger = logger,
       _databasePathProvider = databasePathProvider ?? getDatabasesPath,
       _openConnection = openConnection ?? _openSqlCipherDatabase,
       _closeTimeout = closeTimeout;

  final AppLogger _logger;
  final DatabasePathProvider _databasePathProvider;
  final SqlCipherDatabaseOpener _openConnection;
  final Duration _closeTimeout;
  final StreamController<DatabaseLifecycleState> _states =
      StreamController<DatabaseLifecycleState>.broadcast(sync: true);
  DatabaseLifecycleState _state = const DatabaseLifecycleState.locked();
  Database? _database;
  Future<void>? _openFuture;
  Future<void>? _closeFuture;
  Completer<void>? _leasesDrained;
  int _activeLeases = 0;
  int _generation = 0;

  static const _databaseName = 'note_secret_search.db';
  static const _databaseVersion = 3;

  @override
  DatabaseLifecycleState get state => _state;

  @override
  Stream<DatabaseLifecycleState> get states => _states.stream;

  @override
  Future<void> open(DatabaseSessionKeys sessionKeys) {
    if (_state.status != DatabaseLifecycleStatus.locked) {
      return Future<void>.error(
        const DatabaseLifecycleException('database_invalid_transition'),
      );
    }

    _generation += 1;
    final generation = _generation;
    _emit(
      const DatabaseLifecycleState(
        status: DatabaseLifecycleStatus.opening,
        openingStage: 'opening_connection',
      ),
    );
    final openFuture = _performOpen(sessionKeys, generation);
    _openFuture = openFuture;
    return openFuture;
  }

  Future<void> _performOpen(
    DatabaseSessionKeys sessionKeys,
    int generation,
  ) async {
    Database? connection;
    try {
      final databasesPath = await _databasePathProvider();
      final path = p.join(databasesPath, _databaseName);
      final password = sessionKeys.withDatabaseKey(_encodeDatabasePassword);
      connection = await _openConnection(
        path: path,
        password: password,
        version: _databaseVersion,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      );
      await _ensureDefaultVault(connection);
      if (!_canPublishOpen(generation)) {
        await _closeUnpublished(connection);
        connection = null;
        throw const DatabaseAccessRevokedException();
      }
      _database = connection;
      _emit(const DatabaseLifecycleState(status: DatabaseLifecycleStatus.open));
      _logger.info('sqlcipher_initialized');
    } on DatabaseAccessRevokedException {
      if (connection != null) {
        await _closeUnpublished(connection);
      }
      rethrow;
    } catch (error, stackTrace) {
      if (connection != null) {
        await _closeUnpublished(connection);
      }
      if (!_canPublishOpen(generation)) {
        throw const DatabaseAccessRevokedException();
      }
      _database = null;
      _emit(
        const DatabaseLifecycleState(
          status: DatabaseLifecycleStatus.error,
          errorCode: 'database_open_failed',
        ),
      );
      _logger.error('sqlcipher_open_failed', error, stackTrace);
      throw const DatabaseLifecycleException('database_open_failed');
    } finally {
      _openFuture = null;
    }
  }

  @override
  Future<T> run<T>(Future<T> Function(Database database) operation) async {
    final database = _database;
    if (_state.status != DatabaseLifecycleStatus.open || database == null) {
      throw const DatabaseAccessRevokedException();
    }
    final generation = _generation;
    _activeLeases += 1;
    try {
      final result = await operation(database);
      _throwIfAccessRevoked(database, generation);
      return result;
    } catch (_) {
      _throwIfAccessRevoked(database, generation);
      rethrow;
    } finally {
      _releaseLease();
    }
  }

  @override
  Future<void> close() {
    final activeClose = _closeFuture;
    if (activeClose != null) {
      return activeClose;
    }
    if (_state.status == DatabaseLifecycleStatus.locked && _database == null) {
      return Future<void>.value();
    }

    _generation += 1;
    _emit(
      const DatabaseLifecycleState(status: DatabaseLifecycleStatus.closing),
    );
    final closeFuture = _performClose(_database, _openFuture);
    _closeFuture = closeFuture;
    return closeFuture;
  }

  void _emit(DatabaseLifecycleState next) {
    _state = next;
    _states.add(next);
  }

  Future<void> _createSchema(Database database, int version) async {
    final batch = database.batch();
    for (final statement in DatabaseMigrations.initial()) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      final statements = DatabaseMigrations.forVersion(version);
      if (statements.isEmpty) {
        continue;
      }

      final batch = database.batch();
      for (final statement in statements) {
        batch.execute(statement);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> _ensureDefaultVault(Database database) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.insert(DatabaseSchema.vaults, <String, Object?>{
      'id': 'default',
      'name': '默认保险库',
      'description': '首版默认保险库',
      'is_default': 1,
      'encryption_version': 1,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  void _throwIfAccessRevoked(Database database, int generation) {
    if (_state.status != DatabaseLifecycleStatus.open ||
        _generation != generation ||
        !identical(_database, database)) {
      throw const DatabaseAccessRevokedException();
    }
  }

  void _releaseLease() {
    _activeLeases -= 1;
    if (_activeLeases == 0) {
      final drained = _leasesDrained;
      _leasesDrained = null;
      if (drained != null && !drained.isCompleted) {
        drained.complete();
      }
    }
  }

  Future<void> _performClose(Database? database, Future<void>? opening) async {
    try {
      if (opening != null) {
        try {
          await opening;
        } catch (_) {
          // Opening observes the revoked generation and cleans up its connection.
        }
      }
      await _waitForActiveLeases();
      final connection = database ?? _database;
      await connection?.close();
      if (identical(_database, connection)) {
        _database = null;
      }
      _emit(const DatabaseLifecycleState.locked());
    } catch (error, stackTrace) {
      _emit(
        const DatabaseLifecycleState(
          status: DatabaseLifecycleStatus.error,
          errorCode: 'database_close_failed',
        ),
      );
      _logger.error('sqlcipher_close_failed', error, stackTrace);
      throw const DatabaseLifecycleException('database_close_failed');
    } finally {
      _closeFuture = null;
    }
  }

  bool _canPublishOpen(int generation) {
    return _generation == generation &&
        _state.status == DatabaseLifecycleStatus.opening;
  }

  Future<void> _closeUnpublished(Database database) async {
    try {
      await database.close();
    } catch (_) {
      // The connection was never published and remains inaccessible.
    }
  }

  Future<void> _waitForActiveLeases() async {
    if (_activeLeases == 0) {
      return;
    }
    final drained = _leasesDrained ??= Completer<void>();
    try {
      await drained.future.timeout(_closeTimeout);
    } on TimeoutException {
      _logger.warning('sqlcipher_close_lease_timeout');
    }
  }
}

String _encodeDatabasePassword(List<int> key) {
  final buffer = StringBuffer();
  for (final byte in key) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Future<Database> _openSqlCipherDatabase({
  required String path,
  required String password,
  required int version,
  required OnDatabaseCreateFn onCreate,
  required OnDatabaseVersionChangeFn onUpgrade,
}) {
  return openDatabase(
    path,
    password: password,
    version: version,
    onCreate: onCreate,
    onUpgrade: onUpgrade,
  );
}
