part of 'ai_chat_sensitive_reset_test.dart';

ChatSession _session(String id, {required bool allowPrivateContext}) {
  return ChatSession(
    id: id,
    mode: ChatMode.freeChat,
    title: 'Sensitive session',
    allowPrivateContext: allowPrivateContext,
    archived: false,
    createdAt: DateTime(2026, 7, 14, 12),
    updatedAt: DateTime(2026, 7, 14, 12, 1),
  );
}

ChatStoredMessage _storedMessage(String id, String sessionId, String content) {
  return ChatStoredMessage(
    id: id,
    sessionId: sessionId,
    role: ChatStoredMessageRole.user,
    content: content,
    status: ChatStoredMessageStatus.completed,
    createdAt: DateTime(2026, 7, 14, 12, 2),
  );
}

class _ControllableChatSessionRepository implements ChatSessionRepository {
  _ControllableChatSessionRepository({
    List<ChatSession> sessions = const <ChatSession>[],
    Map<String, List<ChatStoredMessage>> messagesBySession =
        const <String, List<ChatStoredMessage>>{},
    bool delaySessionList = false,
    bool delayMessageList = false,
    bool delaySessionGet = false,
  }) : _sessions = List<ChatSession>.from(sessions),
       _messagesBySession = {
         for (final entry in messagesBySession.entries)
           entry.key: List<ChatStoredMessage>.from(entry.value),
       },
       _sessionListResult = delaySessionList
           ? Completer<List<ChatSession>>()
           : null,
       _messageListResult = delayMessageList
           ? Completer<List<ChatStoredMessage>>()
           : null,
       _sessionGetResult = delaySessionGet ? Completer<ChatSession?>() : null;

  final List<ChatSession> _sessions;
  final Map<String, List<ChatStoredMessage>> _messagesBySession;
  final Completer<List<ChatSession>>? _sessionListResult;
  final Completer<List<ChatStoredMessage>>? _messageListResult;
  final Completer<ChatSession?>? _sessionGetResult;
  final Completer<void> _sessionListRequested = Completer<void>();
  final Completer<void> _messageListRequested = Completer<void>();
  final Completer<void> _sessionGetRequested = Completer<void>();
  final List<ChatStoredMessage> savedMessages = <ChatStoredMessage>[];
  var messageListCalls = 0;
  var sessionGetCalls = 0;

  Future<void> waitForSessionListRequest() => _sessionListRequested.future;

  Future<void> waitForMessageListRequest() => _messageListRequested.future;

  Future<void> waitForSessionGetRequest() => _sessionGetRequested.future;

  void completeSessionList() {
    _sessionListResult?.complete(List<ChatSession>.from(_sessions));
  }

  void completeMessageList(String sessionId) {
    _messageListResult?.complete(
      List<ChatStoredMessage>.from(
        _messagesBySession[sessionId] ?? const <ChatStoredMessage>[],
      ),
    );
  }

  void completeSessionGet(String sessionId) {
    _sessionGetResult?.complete(
      _sessions.where((session) => session.id == sessionId).firstOrNull,
    );
  }

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    sessionGetCalls++;
    final delayed = _sessionGetResult;
    if (delayed != null) {
      if (!_sessionGetRequested.isCompleted) {
        _sessionGetRequested.complete();
      }
      return delayed.future;
    }
    return _sessions.where((session) => session.id == sessionId).firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    messageListCalls++;
    final delayed = _messageListResult;
    if (delayed != null) {
      if (!_messageListRequested.isCompleted) {
        _messageListRequested.complete();
      }
      return delayed.future;
    }
    return List<ChatStoredMessage>.from(
      _messagesBySession[sessionId] ?? const <ChatStoredMessage>[],
    );
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    final delayed = _sessionListResult;
    if (delayed != null) {
      if (!_sessionListRequested.isCompleted) {
        _sessionListRequested.complete();
      }
      return delayed.future;
    }
    return List<ChatSession>.from(_sessions);
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {
    savedMessages.removeWhere((item) => item.id == message.id);
    savedMessages.add(message);
    final messages = _messagesBySession.putIfAbsent(
      message.sessionId,
      () => <ChatStoredMessage>[],
    );
    messages.removeWhere((item) => item.id == message.id);
    messages.add(message);
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    _sessions.removeWhere((item) => item.id == session.id);
    _sessions.add(session);
  }
}

class _ImmediateLlmEngine implements LlmEngine {
  LlmInferenceRequest? lastRequest;

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    lastRequest = request;
    return LlmInferenceResponse(
      text: 'answer',
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

class _ThrowingLlmEngine extends _ImmediateLlmEngine {
  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    throw StateError('sensitive generation failure');
  }
}

class _ControllableLlmEngine extends _ImmediateLlmEngine {
  final Completer<void> _requested = Completer<void>();
  final Completer<LlmInferenceResponse> _result =
      Completer<LlmInferenceResponse>();

  Future<void> waitForRequest() => _requested.future;

  void complete(LlmInferenceResponse response) {
    _result.complete(response);
  }

  void completeError(Object error) {
    _result.completeError(error);
  }

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) {
    if (!_requested.isCompleted) {
      _requested.complete();
    }
    return _result.future;
  }
}
