part of 'chat_session_providers_test.dart';

class _TestAppDatabase implements AppDatabase {
  _TestAppDatabase(this._database);

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
  Future<T> transaction<T>(
    Future<T> Function(DatabaseExecutor executor) operation,
  ) async {
    if (_state.status != DatabaseLifecycleStatus.open) {
      throw const DatabaseAccessRevokedException();
    }
    return _database.transaction(operation);
  }

  @override
  Future<void> close() async {
    _state = const DatabaseLifecycleState(
      status: DatabaseLifecycleStatus.closing,
    );
    await _database.close();
    _state = const DatabaseLifecycleState.locked();
  }
}

class _InMemoryDatabase implements Database {
  final Map<String, List<Map<String, Object?>>> _tables =
      <String, List<Map<String, Object?>>>{};

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final rows = _tables.putIfAbsent(table, () => <Map<String, Object?>>[]);
    final identifier = values['id'];
    if (identifier != null) {
      rows.removeWhere((row) => row['id'] == identifier);
    }
    rows.add(Map<String, Object?>.from(values));
    return 1;
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    if (sql.contains('INSERT INTO chat_sessions') &&
        arguments != null &&
        arguments.length == 8) {
      return insert('chat_sessions', <String, Object?>{
        'id': arguments[0],
        'mode': arguments[1],
        'title': arguments[2],
        'allow_private_context': arguments[3],
        'last_model_id': arguments[4],
        'archived': arguments[5],
        'created_at': arguments[6],
        'updated_at': arguments[7],
      });
    }
    throw UnsupportedError('Unsupported raw insert in chat database fake.');
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final rows = List<Map<String, Object?>>.from(
      _tables[table] ?? const <Map<String, Object?>>[],
    );
    final filtered = rows
        .where((row) => _matchesWhere(row, where, whereArgs))
        .toList(growable: false);
    final sorted = _sortRows(filtered, orderBy);
    if (limit != null && sorted.length > limit) {
      return sorted.take(limit).toList(growable: false);
    }
    return sorted;
  }

  bool _matchesWhere(
    Map<String, Object?> row,
    String? where,
    List<Object?>? whereArgs,
  ) {
    if (where == null || whereArgs == null || whereArgs.isEmpty) {
      return true;
    }

    if (where == 'id = ?') {
      return row['id'] == whereArgs.first;
    }
    if (where == 'session_id = ?') {
      return row['session_id'] == whereArgs.first;
    }
    return true;
  }

  List<Map<String, Object?>> _sortRows(
    List<Map<String, Object?>> rows,
    String? orderBy,
  ) {
    final sorted = List<Map<String, Object?>>.from(rows);
    if (orderBy == null) {
      return sorted;
    }

    switch (orderBy) {
      case 'updated_at DESC, id ASC':
        sorted.sort((left, right) {
          final byUpdatedAt = (right['updated_at'] as int).compareTo(
            left['updated_at'] as int,
          );
          return byUpdatedAt != 0
              ? byUpdatedAt
              : (left['id']! as String).compareTo(right['id']! as String);
        });
      case 'created_at ASC, id ASC':
        sorted.sort((left, right) {
          final byCreatedAt = (left['created_at'] as int).compareTo(
            right['created_at'] as int,
          );
          return byCreatedAt != 0
              ? byCreatedAt
              : (left['id']! as String).compareTo(right['id']! as String);
        });
    }

    return sorted;
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatSessionRepository implements ChatSessionRepository {
  _FakeChatSessionRepository({
    List<ChatSession>? sessions,
    Map<String, List<ChatStoredMessage>>? messagesBySession,
  }) : _sessions = sessions ?? <ChatSession>[],
       _messagesBySession =
           messagesBySession ?? <String, List<ChatStoredMessage>>{};

  final List<ChatSession> _sessions;
  final Map<String, List<ChatStoredMessage>> _messagesBySession;

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    return _sessions.where((session) => session.id == sessionId).firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    return _messagesBySession[sessionId] ?? const <ChatStoredMessage>[];
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    final sorted = List<ChatSession>.from(_sessions)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {
    final messages = _messagesBySession.putIfAbsent(
      message.sessionId,
      () => <ChatStoredMessage>[],
    );
    messages.removeWhere((item) => item.id == message.id);
    messages.add(message);
    messages.sort((left, right) => left.createdAt.compareTo(right.createdAt));
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    _sessions.removeWhere((item) => item.id == session.id);
    _sessions.add(session);
  }
}
