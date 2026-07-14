import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

const _llmModel = ModelRegistryEntry(
  id: 'llm-sensitive',
  type: 'llm',
  provider: 'test',
  name: 'Sensitive LLM',
  version: '1',
  sizeBytes: 1024,
  quantization: 'Q4',
  minRamMb: 512,
  recommendedTier: 'test',
  localPath: '/private/models/sensitive.gguf',
  checksum: null,
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _manualItem = ChatContextItem(
  id: 'manual-secret',
  type: ChatContextItemType.secret,
  title: 'Private account',
  preview: 'private preview',
  summary: 'private summary',
);

void main() {
  test(
    'startNewSession resets privacy, messages, selection, errors, and restoration',
    () async {
      final repository = _ControllableChatSessionRepository(
        sessions: [_session('session-old', allowPrivateContext: true)],
        messagesBySession: {
          'session-old': [
            _storedMessage('message-old', 'session-old', 'old plaintext'),
          ],
        },
      );
      final container = _buildContainer(
        repository: repository,
        llmEngine: _ThrowingLlmEngine(),
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.selectSession('session-old');
      controller.setAllowPrivateContext(true);
      controller.setManualItems(const [_manualItem]);
      await controller.send('create an error');

      expect(controller.state.messages, isNotEmpty);
      expect(controller.state.allowPrivateContext, isTrue);
      expect(controller.state.manualItems, isNotEmpty);
      expect(controller.state.currentSessionId, isNotNull);
      expect(controller.state.errorMessage, isNotNull);

      await controller.startNewSession();

      _expectBlankConversation(container, controller);
    },
  );

  test('resetForLock resets privacy and shared chat selection', () async {
    final repository = _ControllableChatSessionRepository(
      sessions: [_session('session-lock', allowPrivateContext: true)],
      messagesBySession: {
        'session-lock': [
          _storedMessage('message-lock', 'session-lock', 'locked plaintext'),
        ],
      },
    );
    final container = _buildContainer(repository: repository, llmEngine: _ThrowingLlmEngine());
    addTearDown(container.dispose);

    final controller = container.read(privateQaChatControllerProvider.notifier);
    await controller.selectSession('session-lock');
    controller.setAllowPrivateContext(true);
    controller.setManualItems(const [_manualItem]);
    await controller.send('create lock error');

    expect(controller.state.errorMessage, isNotNull);

    controller.resetForLock();

    _expectBlankConversation(container, controller);
  });

  test(
    'stale restoreSessionIfNeeded completion cannot repopulate after lock reset',
    () async {
      final repository = _ControllableChatSessionRepository(
        sessions: [_session('session-restore', allowPrivateContext: true)],
        messagesBySession: {
          'session-restore': [
            _storedMessage(
              'message-restore',
              'session-restore',
              'restored plaintext',
            ),
          ],
        },
        delaySessionList: true,
      );
      final container = _buildContainer(
        repository: repository,
        llmEngine: _ImmediateLlmEngine(),
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      final restoreFuture = controller.restoreSessionIfNeeded();
      await repository.waitForSessionListRequest();

      controller.resetForLock();
      repository.completeSessionList();
      await restoreFuture;

      _expectBlankConversation(container, controller);
      expect(repository.messageListCalls, 0);
    },
  );

  test(
    'stale selectSession completion cannot repopulate after startNewSession',
    () async {
      final repository = _ControllableChatSessionRepository(
        sessions: [_session('session-select', allowPrivateContext: true)],
        messagesBySession: {
          'session-select': [
            _storedMessage(
              'message-select',
              'session-select',
              'selected plaintext',
            ),
          ],
        },
        delayMessageList: true,
      );
      final container = _buildContainer(
        repository: repository,
        llmEngine: _ImmediateLlmEngine(),
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      final selectFuture = controller.selectSession('session-select');
      await repository.waitForMessageListRequest();

      await controller.startNewSession();
      repository.completeMessageList('session-select');
      await selectFuture;

      _expectBlankConversation(container, controller);
      expect(repository.sessionGetCalls, 0);
    },
  );

  test(
    'stale selectSession second await cannot repopulate after lock reset',
    () async {
      final repository = _ControllableChatSessionRepository(
        sessions: [_session('session-select', allowPrivateContext: true)],
        messagesBySession: {
          'session-select': [
            _storedMessage(
              'message-select',
              'session-select',
              'selected plaintext',
            ),
          ],
        },
        delaySessionGet: true,
      );
      final container = _buildContainer(
        repository: repository,
        llmEngine: _ImmediateLlmEngine(),
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      final selectFuture = controller.selectSession('session-select');
      await repository.waitForSessionGetRequest();

      controller.resetForLock();
      repository.completeSessionGet('session-select');
      await selectFuture;

      _expectBlankConversation(container, controller);
    },
  );

  test(
    'stale send completion cannot repopulate messages after lock reset',
    () async {
      final repository = _ControllableChatSessionRepository();
      final llmEngine = _ControllableLlmEngine();
      final container = _buildContainer(
        repository: repository,
        llmEngine: llmEngine,
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      controller.setAllowPrivateContext(true);
      controller.setManualItems(const [_manualItem]);
      final sendFuture = controller.send('sensitive prompt');
      await llmEngine.waitForRequest();

      expect(controller.state.sending, isTrue);
      expect(controller.state.messages, hasLength(2));

      controller.resetForLock();
      llmEngine.complete(
        const LlmInferenceResponse(
          text: 'stale assistant plaintext',
          finishReason: 'stop',
          usedPrivateContext: true,
        ),
      );
      await sendFuture;

      _expectBlankConversation(container, controller);
      expect(
        repository.savedMessages.where(
          (message) => message.role == ChatStoredMessageRole.assistant,
        ),
        isEmpty,
      );
    },
  );

  test(
    'stale failed send cannot repopulate errors after lock reset',
    () async {
      final repository = _ControllableChatSessionRepository();
      final llmEngine = _ControllableLlmEngine();
      final container = _buildContainer(
        repository: repository,
        llmEngine: llmEngine,
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      final sendFuture = controller.send('sensitive prompt');
      await llmEngine.waitForRequest();

      controller.resetForLock();
      llmEngine.completeError(StateError('stale sensitive failure'));
      await sendFuture;

      _expectBlankConversation(container, controller);
      expect(
        repository.savedMessages.where(
          (message) => message.status == ChatStoredMessageStatus.failed,
        ),
        isEmpty,
      );
    },
  );
}

ProviderContainer _buildContainer({
  required ChatSessionRepository repository,
  required LlmEngine llmEngine,
}) {
  return ProviderContainer(
    overrides: [
      sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
      chatSessionRepositoryProvider.overrideWithValue(repository),
      llmEngineProvider.overrideWithValue(llmEngine),
      localLlmReadinessProvider.overrideWith(
        (ref) async => const LocalLlmReadiness(
          ready: true,
          reason: 'ready',
          activeModel: _llmModel,
          runtimeState: LlmRuntimeState(
            ready: true,
            reason: 'ready',
            status: LlmRuntimeStatus.ready,
            modelPath: '/private/models/sensitive.gguf',
          ),
        ),
      ),
      semanticSearchReadinessProvider.overrideWith(
        (ref) async => const SemanticSearchReadiness(
          ready: false,
          reason: 'semantic retrieval disabled for controller test',
        ),
      ),
    ],
  );
}

void _expectBlankConversation(
  ProviderContainer container,
  AiChatConversationController controller,
) {
  expect(controller.state.messages, isEmpty);
  expect(controller.state.sending, isFalse);
  expect(controller.state.allowPrivateContext, isFalse);
  expect(controller.state.manualItems, isEmpty);
  expect(controller.state.currentSessionId, isNull);
  expect(controller.state.errorMessage, isNull);
  expect(controller.state.suppressSessionRestore, isTrue);
  expect(container.read(currentChatSessionIdProvider), isNull);
  expect(container.read(suppressRestoredChatSessionProvider), isTrue);
}

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
  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
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
