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
