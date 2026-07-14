import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_message.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

part 'ai_chat_concurrency_test_fakes.dart';

const _llmModel = ModelRegistryEntry(
  id: 'llm-concurrency',
  type: 'llm',
  provider: 'test',
  name: 'Concurrency LLM',
  version: '1',
  sizeBytes: 1024,
  quantization: 'Q4',
  minRamMb: 512,
  recommendedTier: 'test',
  localPath: '/models/concurrency.gguf',
  checksum: null,
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _ready = LocalLlmReadiness(
  ready: true,
  reason: 'ready',
  activeModel: _llmModel,
  runtimeState: LlmRuntimeState(
    ready: true,
    reason: 'ready',
    status: LlmRuntimeStatus.ready,
  ),
);

void main() {
  test(
    'latest same-controller selection wins when the older load completes last',
    () async {
      final repository = _ChatTestRepository(
        sessions: [
          _session('session-a', ChatMode.freeChat),
          _session('session-b', ChatMode.freeChat),
        ],
        messagesBySession: {
          'session-a': [_message('message-a', 'session-a', 'message A')],
          'session-b': [_message('message-b', 'session-b', 'message B')],
        },
        blockedMessageSessionIds: const {'session-a'},
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      final selectA = controller.selectSession('session-a');
      await repository.waitForMessageList('session-a');

      await controller.selectSession('session-b');
      repository.completeMessageList('session-a');
      await selectA;

      _expectSelected(controller, sessionId: 'session-b', text: 'message B');
      expect(container.read(currentChatSessionIdProvider), 'session-b');
    },
  );

  test('latest selection wins across free and private controllers', () async {
    final repository = _ChatTestRepository(
      sessions: [
        _session('session-a', ChatMode.freeChat),
        _session('session-b', ChatMode.privateQa),
      ],
      messagesBySession: {
        'session-a': [_message('message-a', 'session-a', 'free A')],
        'session-b': [_message('message-b', 'session-b', 'private B')],
      },
      blockedMessageSessionIds: const {'session-a'},
    );
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);

    final freeController = container.read(freeChatControllerProvider.notifier);
    final privateController = container.read(
      privateQaChatControllerProvider.notifier,
    );
    final selectA = freeController.selectSession('session-a');
    await repository.waitForMessageList('session-a');

    await privateController.selectSession('session-b');
    await freeController.restoreSessionIfNeeded();
    repository.completeMessageList('session-a');
    await selectA;

    _expectSelected(
      privateController,
      sessionId: 'session-b',
      text: 'private B',
    );
    expect(freeController.state.currentSessionId, isNull);
    expect(freeController.state.messages, isEmpty);
    expect(container.read(currentChatSessionIdProvider), 'session-b');
  });

  test(
    'explicit selection prevents an older restore completion from overwriting it',
    () async {
      final repository = _ChatTestRepository(
        sessions: [
          _session('session-a', ChatMode.freeChat),
          _session('session-b', ChatMode.freeChat),
        ],
        messagesBySession: {
          'session-a': [_message('message-a', 'session-a', 'restored A')],
          'session-b': [_message('message-b', 'session-b', 'selected B')],
        },
        delaySessionList: true,
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      final restore = controller.restoreSessionIfNeeded();
      await repository.waitForSessionList();

      await controller.selectSession('session-b');
      repository.completeSessionList();
      await restore;

      _expectSelected(controller, sessionId: 'session-b', text: 'selected B');
      expect(container.read(currentChatSessionIdProvider), 'session-b');
    },
  );

  test(
    'send binds its origin before readiness and never redirects writes to B',
    () async {
      final readiness = _ControllableReadiness();
      final repository = _ChatTestRepository(
        sessions: [
          _session('session-a', ChatMode.freeChat),
          _session('session-b', ChatMode.freeChat),
        ],
        messagesBySession: {
          'session-a': [_message('message-a', 'session-a', 'origin A')],
          'session-b': [_message('message-b', 'session-b', 'selected B')],
        },
      );
      final container = _buildContainer(
        repository: repository,
        readiness: readiness,
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.selectSession('session-a');
      final send = controller.send('answer from A');
      await readiness.waitForRequest();

      await controller.selectSession('session-b');
      readiness.complete(_ready);
      await send;

      expect(
        repository.messageWrites.map((message) => message.sessionId).toSet(),
        {'session-a'},
      );
      expect(repository.sessionWrites.map((session) => session.id).toSet(), {
        'session-a',
      });
      _expectCleanSelectedB(controller);
    },
  );

  test('late successful send persists only to A and leaves B clean', () async {
    final llmEngine = _ControllableLlmEngine();
    final repository = _repositoryForLateSend();
    final container = _buildContainer(
      repository: repository,
      llmEngine: llmEngine,
    );
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.selectSession('session-a');
    final send = controller.send('late success');
    await llmEngine.waitForRequest();

    await controller.selectSession('session-b');
    _expectCleanSelectedB(controller);
    llmEngine.complete('answer for A');
    await send;

    _expectWritesOnlySessionA(repository);
    expect(repository.messageWrites.last.role, ChatStoredMessageRole.assistant);
    _expectCleanSelectedB(controller);
  });

  test('late failed send persists only to A and leaves B clean', () async {
    final llmEngine = _ControllableLlmEngine();
    final repository = _repositoryForLateSend();
    final container = _buildContainer(
      repository: repository,
      llmEngine: llmEngine,
    );
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.selectSession('session-a');
    final send = controller.send('late failure');
    await llmEngine.waitForRequest();

    await controller.selectSession('session-b');
    _expectCleanSelectedB(controller);
    llmEngine.completeError(StateError('answer failed for A'));
    await send;

    _expectWritesOnlySessionA(repository);
    expect(repository.messageWrites.last.role, ChatStoredMessageRole.system);
    expect(
      repository.messageWrites.last.status,
      ChatStoredMessageStatus.failed,
    );
    _expectCleanSelectedB(controller);
  });

  test(
    'reloading the origin session while send is in flight still shows its answer',
    () async {
      final llmEngine = _ControllableLlmEngine();
      final repository = _ChatTestRepository(
        sessions: [_session('session-a', ChatMode.freeChat)],
      );
      final container = _buildContainer(
        repository: repository,
        llmEngine: llmEngine,
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.selectSession('session-a');
      final send = controller.send('hello A');
      await llmEngine.waitForRequest();

      await controller.selectSession('session-a');
      expect(controller.state.messages, hasLength(1));
      expect(controller.state.messages.single.role, ChatMessageRole.user);
      expect(controller.state.messages.single.text, 'hello A');

      llmEngine.complete('answer A');
      await send;

      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages[0].text, 'hello A');
      expect(controller.state.messages[1].role, ChatMessageRole.assistant);
      expect(controller.state.messages[1].text, 'answer A');
      expect(controller.state.sending, isFalse);
    },
  );
}

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
