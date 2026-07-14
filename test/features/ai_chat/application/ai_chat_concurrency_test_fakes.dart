part of 'ai_chat_concurrency_test.dart';

class _ChatTestRepository implements ChatSessionRepository {
  _ChatTestRepository({
    List<ChatSession> sessions = const <ChatSession>[],
    Map<String, List<ChatStoredMessage>> messagesBySession =
        const <String, List<ChatStoredMessage>>{},
    Set<String> blockedMessageSessionIds = const <String>{},
    bool delaySessionList = false,
  }) : _sessions = {for (final session in sessions) session.id: session},
       _messagesBySession = {
         for (final entry in messagesBySession.entries)
           entry.key: List<ChatStoredMessage>.from(entry.value),
       },
       _blockedMessageSessionIds = Set<String>.from(blockedMessageSessionIds),
       _sessionListResult = delaySessionList
           ? Completer<List<ChatSession>>()
           : null;

  final Map<String, ChatSession> _sessions;
  final Map<String, List<ChatStoredMessage>> _messagesBySession;
  final Set<String> _blockedMessageSessionIds;
  final Completer<List<ChatSession>>? _sessionListResult;
  final Map<String, Completer<void>> _messageListRequests = {};
  final Map<String, Completer<List<ChatStoredMessage>>> _messageListResults =
      {};
  final Completer<void> _sessionListRequest = Completer<void>();

  final List<ChatSession> sessionWrites = <ChatSession>[];
  final List<ChatStoredMessage> messageWrites = <ChatStoredMessage>[];

  Future<void> waitForMessageList(String sessionId) {
    return _messageListRequests
        .putIfAbsent(sessionId, Completer<void>.new)
        .future;
  }

  Future<void> waitForSessionList() => _sessionListRequest.future;

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

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    return _sessions[sessionId];
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
