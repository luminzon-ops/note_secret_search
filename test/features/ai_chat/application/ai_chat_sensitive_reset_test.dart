import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_context_projector.dart';
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
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';

part 'ai_chat_sensitive_reset_test_fakes.dart';

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
    'selectSession resets private chat choices before the next send',
    () async {
      final repository = _ControllableChatSessionRepository(
        sessions: [
          _session('session-a', allowPrivateContext: true),
          _session('session-b', allowPrivateContext: true),
        ],
        messagesBySession: {
          'session-a': [
            _storedMessage('message-a', 'session-a', 'session A message'),
          ],
          'session-b': [
            _storedMessage('message-b', 'session-b', 'session B message'),
          ],
        },
      );
      final llmEngine = _ImmediateLlmEngine();
      final container = _buildContainer(
        repository: repository,
        llmEngine: llmEngine,
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.selectSession('session-a');
      controller.setBackendPreference(ChatBackendPreference.external);
      controller.setManualItems(const [_manualItem]);

      await controller.selectSession('session-b');

      expect(controller.state.currentSessionId, 'session-b');
      expect(controller.state.allowPrivateContext, isTrue);
      expect(controller.state.backendPreference, ChatBackendPreference.local);
      expect(controller.state.manualItems, isEmpty);
      expect(
        controller.state.messages.map((message) => message.text),
        contains('session B message'),
      );

      await controller.send('question for session B');

      expect(llmEngine.lastRequest, isNotNull);
      expect(llmEngine.lastRequest!.prompt, contains('question for session B'));
      expect(llmEngine.lastRequest!.usedPrivateContext, isFalse);

      controller.setBackendPreference(ChatBackendPreference.external);
      controller.setManualItems(const [_manualItem]);
      await controller.selectSession('session-b');

      expect(controller.state.backendPreference, ChatBackendPreference.local);
      expect(controller.state.manualItems, isEmpty);
    },
  );

  test('automatic session restore resets private chat choices', () async {
    final repository = _ControllableChatSessionRepository(
      sessions: [_session('session-restored', allowPrivateContext: true)],
      messagesBySession: {
        'session-restored': [
          _storedMessage(
            'message-restored',
            'session-restored',
            'restored message',
          ),
        ],
      },
    );
    final container = _buildContainer(
      repository: repository,
      llmEngine: _ImmediateLlmEngine(),
    );
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    controller.setBackendPreference(ChatBackendPreference.external);
    controller.setManualItems(const [_manualItem]);

    await controller.restoreSessionIfNeeded();

    expect(controller.state.currentSessionId, 'session-restored');
    expect(controller.state.allowPrivateContext, isTrue);
    expect(controller.state.backendPreference, ChatBackendPreference.local);
    expect(controller.state.manualItems, isEmpty);
  });

  test('failed selection preserves current private chat choices', () async {
    final repository = _ControllableChatSessionRepository(
      sessions: [_session('session-current', allowPrivateContext: true)],
    );
    final container = _buildContainer(
      repository: repository,
      llmEngine: _ImmediateLlmEngine(),
    );
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.selectSession('session-current');
    controller.setBackendPreference(ChatBackendPreference.external);
    controller.setManualItems(const [_manualItem]);

    await controller.selectSession('missing-session');

    expect(controller.state.currentSessionId, 'session-current');
    expect(controller.state.backendPreference, ChatBackendPreference.external);
    expect(controller.state.manualItems, const [_manualItem]);
  });

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
      controller.setBackendPreference(ChatBackendPreference.external);
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
    final container = _buildContainer(
      repository: repository,
      llmEngine: _ThrowingLlmEngine(),
    );
    addTearDown(container.dispose);

    final controller = container.read(privateQaChatControllerProvider.notifier);
    await controller.selectSession('session-lock');
    controller.setBackendPreference(ChatBackendPreference.external);
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
      final requestId = llmEngine.lastRequest!.requestId!;

      controller.resetForLock();
      await Future<void>.delayed(Duration.zero);
      expect(llmEngine.cancelledRequestIds, <String>[requestId]);
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

  test('stale failed send cannot repopulate errors after lock reset', () async {
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
  });

  test('startNewSession cancels the active generation request', () async {
    final repository = _ControllableChatSessionRepository();
    final llmEngine = _ControllableLlmEngine();
    final container = _buildContainer(
      repository: repository,
      llmEngine: llmEngine,
    );
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    final sendFuture = controller.send('cancel on new session');
    await llmEngine.waitForRequest();
    final requestId = llmEngine.lastRequest!.requestId!;

    await controller.startNewSession();

    expect(llmEngine.cancelledRequestIds, <String>[requestId]);
    llmEngine.complete(
      const LlmInferenceResponse(
        text: 'late response',
        finishReason: 'stop',
        usedPrivateContext: false,
      ),
    );
    await sendFuture;
    _expectBlankConversation(container, controller);
  });

  test('stop persists only the stable cancellation message', () async {
    final repository = _ControllableChatSessionRepository();
    final llmEngine = _ControllableLlmEngine();
    final container = _buildContainer(
      repository: repository,
      llmEngine: llmEngine,
    );
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    final sendFuture = controller.send('stop this request');
    await llmEngine.waitForRequest();

    await controller.stopGeneration();
    llmEngine.completeError(const LlmGenerationCancelledException());
    await sendFuture;

    final failed = repository.savedMessages.singleWhere(
      (message) => message.status == ChatStoredMessageStatus.failed,
    );
    expect(failed.role, ChatStoredMessageRole.system);
    expect(failed.content, '生成已停止。');
    expect(failed.content, isNot(contains('/private/models')));
    expect(controller.state.errorMessage, '生成已停止。');
  });
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
      searchConfigurationProvider.overrideWith(
        (ref) async => SearchConfiguration.defaults(),
      ),
      chatContextProjectorProvider.overrideWithValue(
        const _SensitiveTestContextProjector(),
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
  expect(controller.state.backendPreference, ChatBackendPreference.local);
  expect(controller.state.allowPrivateContext, isFalse);
  expect(controller.state.manualItems, isEmpty);
  expect(controller.state.currentSessionId, isNull);
  expect(controller.state.errorMessage, isNull);
  expect(controller.state.suppressSessionRestore, isTrue);
  expect(container.read(currentChatSessionIdProvider), isNull);
  expect(container.read(suppressRestoredChatSessionProvider), isTrue);
}
