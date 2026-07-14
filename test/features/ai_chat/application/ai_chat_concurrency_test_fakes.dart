part of 'ai_chat_concurrency_test.dart';

ProviderContainer _buildContainer({
  required _ChatTestRepository repository,
  LlmEngine? llmEngine,
  _ControllableReadiness? readiness,
}) {
  return ProviderContainer(
    overrides: [
      sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
      chatSessionRepositoryProvider.overrideWithValue(repository),
      llmEngineProvider.overrideWithValue(
        llmEngine ?? const _ImmediateLlmEngine(),
      ),
      localLlmReadinessProvider.overrideWith(
        (ref) => readiness?.load() ?? Future.value(_ready),
      ),
    ],
  );
}

_ChatTestRepository _repositoryForLateSend() {
  return _ChatTestRepository(
    sessions: [
      _session('session-a', ChatMode.freeChat),
      _session('session-b', ChatMode.freeChat),
    ],
    messagesBySession: {
      'session-a': [_message('message-a', 'session-a', 'origin A')],
      'session-b': [_message('message-b', 'session-b', 'selected B')],
    },
  );
}

void _expectSelected(
  AiChatConversationController controller, {
  required String sessionId,
  required String text,
}) {
  expect(controller.state.currentSessionId, sessionId);
  expect(controller.state.messages, hasLength(1));
  expect(controller.state.messages.single.text, text);
}

void _expectCleanSelectedB(AiChatConversationController controller) {
  _expectSelected(controller, sessionId: 'session-b', text: 'selected B');
  expect(controller.state.sending, isFalse);
  expect(controller.state.errorMessage, isNull);
}

void _expectWritesOnlySessionA(_ChatTestRepository repository) {
  expect(repository.messageWrites, hasLength(2));
  expect(repository.messageWrites.map((message) => message.sessionId).toSet(), {
    'session-a',
  });
  expect(repository.sessionWrites.map((session) => session.id).toSet(), {
    'session-a',
  });
}

ChatSession _session(String id, ChatMode mode) {
  return ChatSession(
    id: id,
    mode: mode,
    title: id,
    allowPrivateContext: false,
    archived: false,
    createdAt: DateTime(2026, 7, 15, 9),
    updatedAt: DateTime(2026, 7, 15, 9, 1),
  );
}

ChatStoredMessage _message(String id, String sessionId, String content) {
  return ChatStoredMessage(
    id: id,
    sessionId: sessionId,
    role: ChatStoredMessageRole.user,
    content: content,
    status: ChatStoredMessageStatus.completed,
    createdAt: DateTime(2026, 7, 15, 9, 2),
  );
}

class _ChatTestRepository implements ChatSessionRepository {
  _ChatTestRepository({
    List<ChatSession> sessions = const <ChatSession>[],
    Map<String, List<ChatStoredMessage>> messagesBySession =
        const <String, List<ChatStoredMessage>>{},
    Set<String> blockedSessionGetIds = const <String>{},
    Set<String> blockedMessageSessionIds = const <String>{},
    bool delaySessionList = false,
    bool delaySessionSave = false,
  }) : _sessions = {for (final session in sessions) session.id: session},
       _messagesBySession = {
         for (final entry in messagesBySession.entries)
           entry.key: List<ChatStoredMessage>.from(entry.value),
       },
       _blockedSessionGetIds = Set<String>.from(blockedSessionGetIds),
       _blockedMessageSessionIds = Set<String>.from(blockedMessageSessionIds),
       _sessionListResult = delaySessionList
           ? Completer<List<ChatSession>>()
           : null,
       _sessionSaveResult = delaySessionSave ? Completer<void>() : null;

  final Map<String, ChatSession> _sessions;
  final Map<String, List<ChatStoredMessage>> _messagesBySession;
  final Set<String> _blockedSessionGetIds;
  final Set<String> _blockedMessageSessionIds;
  final Completer<List<ChatSession>>? _sessionListResult;
  final Completer<void>? _sessionSaveResult;
  final Map<String, Completer<void>> _sessionGetRequests = {};
  final Map<String, Completer<ChatSession?>> _sessionGetResults = {};
  final Map<String, Completer<void>> _messageListRequests = {};
  final Map<String, Completer<List<ChatStoredMessage>>> _messageListResults =
      {};
  final Completer<void> _sessionListRequest = Completer<void>();
  final Completer<ChatSession> _sessionSaveRequest = Completer<ChatSession>();

  final List<ChatSession> sessionWrites = <ChatSession>[];
  final List<ChatStoredMessage> messageWrites = <ChatStoredMessage>[];

  Future<void> waitForMessageList(String sessionId) {
    return _messageListRequests
        .putIfAbsent(sessionId, Completer<void>.new)
        .future;
  }

  Future<void> waitForSessionGet(String sessionId) {
    return _sessionGetRequests
        .putIfAbsent(sessionId, Completer<void>.new)
        .future;
  }

  Future<void> waitForSessionList() => _sessionListRequest.future;

  Future<ChatSession> waitForSessionSave() => _sessionSaveRequest.future;

  void completeSessionGet(String sessionId) {
    final result = _sessionGetResults[sessionId];
    if (result == null || result.isCompleted) {
      return;
    }
    result.complete(_sessions[sessionId]);
  }

  void completeMessageList(String sessionId) {
    final result = _messageListResults[sessionId];
    if (result == null || result.isCompleted) {
      return;
    }
    result.complete(
      List<ChatStoredMessage>.from(
        _messagesBySession[sessionId] ?? const <ChatStoredMessage>[],
      ),
    );
  }

  void completeSessionList() {
    final result = _sessionListResult;
    if (result == null || result.isCompleted) {
      return;
    }
    result.complete(List<ChatSession>.from(_sessions.values));
  }

  void completeSessionSave() {
    final result = _sessionSaveResult;
    if (result != null && !result.isCompleted) {
      result.complete();
    }
  }

  @override
  Future<ChatSession?> getSession(String sessionId) {
    if (!_blockedSessionGetIds.contains(sessionId)) {
      return Future.value(_sessions[sessionId]);
    }

    final request = _sessionGetRequests.putIfAbsent(
      sessionId,
      Completer<void>.new,
    );
    if (!request.isCompleted) {
      request.complete();
    }
    return _sessionGetResults
        .putIfAbsent(sessionId, Completer<ChatSession?>.new)
        .future;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) {
    if (!_blockedMessageSessionIds.contains(sessionId)) {
      return Future.value(
        List<ChatStoredMessage>.from(
          _messagesBySession[sessionId] ?? const <ChatStoredMessage>[],
        ),
      );
    }

    final request = _messageListRequests.putIfAbsent(
      sessionId,
      Completer<void>.new,
    );
    if (!request.isCompleted) {
      request.complete();
    }
    return _messageListResults
        .putIfAbsent(sessionId, Completer<List<ChatStoredMessage>>.new)
        .future;
  }

  @override
  Future<List<ChatSession>> listSessions() {
    final result = _sessionListResult;
    if (result == null) {
      return Future.value(List<ChatSession>.from(_sessions.values));
    }
    if (!_sessionListRequest.isCompleted) {
      _sessionListRequest.complete();
    }
    return result.future;
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {
    messageWrites.add(message);
    final messages = _messagesBySession.putIfAbsent(
      message.sessionId,
      () => <ChatStoredMessage>[],
    );
    messages.removeWhere((item) => item.id == message.id);
    messages.add(message);
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    final result = _sessionSaveResult;
    if (result != null) {
      if (!_sessionSaveRequest.isCompleted) {
        _sessionSaveRequest.complete(session);
      }
      await result.future;
    }
    sessionWrites.add(session);
    _sessions[session.id] = session;
  }
}

class _ControllableReadiness {
  final Completer<void> _request = Completer<void>();
  final Completer<LocalLlmReadiness> _result = Completer<LocalLlmReadiness>();

  Future<void> waitForRequest() => _request.future;

  Future<LocalLlmReadiness> load() {
    if (!_request.isCompleted) {
      _request.complete();
    }
    return _result.future;
  }

  void complete(LocalLlmReadiness readiness) {
    _result.complete(readiness);
  }

  void completeError(Object error) {
    _result.completeError(error);
  }
}

class _ImmediateLlmEngine implements LlmEngine {
  const _ImmediateLlmEngine();

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    return LlmInferenceResponse(
      text: 'immediate answer',
      finishReason: 'stop',
      usedPrivateContext: request.usedPrivateContext,
    );
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) async {
    return const LlmRuntimeState(
      ready: true,
      reason: 'ready',
      status: LlmRuntimeStatus.ready,
    );
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _ControllableLlmEngine extends _ImmediateLlmEngine {
  final Completer<void> _request = Completer<void>();
  final Completer<LlmInferenceResponse> _result =
      Completer<LlmInferenceResponse>();

  Future<void> waitForRequest() => _request.future;

  void complete(String text) {
    _result.complete(
      LlmInferenceResponse(
        text: text,
        finishReason: 'stop',
        usedPrivateContext: false,
      ),
    );
  }

  void completeError(Object error) {
    _result.completeError(error);
  }

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) {
    if (!_request.isCompleted) {
      _request.complete();
    }
    return _result.future;
  }
}

class _QueuedControllableLlmEngine extends _ImmediateLlmEngine {
  final List<Completer<LlmInferenceResponse>> _results = [
    Completer<LlmInferenceResponse>(),
    Completer<LlmInferenceResponse>(),
  ];
  final Map<int, Completer<void>> _requestWaiters = {};

  var requestCount = 0;

  Future<void> waitForRequestCount(int count) {
    if (requestCount >= count) {
      return Future.value();
    }
    return _requestWaiters.putIfAbsent(count, Completer<void>.new).future;
  }

  void complete(int index, String text) {
    _results[index].complete(
      LlmInferenceResponse(
        text: text,
        finishReason: 'stop',
        usedPrivateContext: false,
      ),
    );
  }

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) {
    final index = requestCount;
    requestCount++;
    for (final entry in _requestWaiters.entries) {
      if (requestCount >= entry.key && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    if (index < _results.length) {
      return _results[index].future;
    }
    return super.generate(request);
  }
}
