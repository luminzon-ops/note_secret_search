import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_context_projector.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/external_chat_gateway.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent_store.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';

const _llmModel = ModelRegistryEntry(
  id: 'llm-1',
  type: 'llm',
  provider: 'builtin',
  name: 'Phi Local',
  version: '1.0.0',
  sizeBytes: 104857600,
  quantization: 'Q4_K_M',
  minRamMb: 2048,
  recommendedTier: 'local',
  localPath: '/data/models/phi.gguf',
  checksum: 'abc',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _embeddingModel = ModelRegistryEntry(
  id: 'embed-1',
  type: 'embedding',
  provider: 'builtin',
  name: 'MiniLM Embedding',
  version: '1.0.2',
  sizeBytes: 10485760,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'mvp',
  localPath: '/data/models/minilm.onnx',
  checksum: 'def',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _externalProvider = ExternalProviderConfig(
  id: 'provider-1',
  providerType: ExternalProviderType.openAiCompatible,
  displayName: 'OpenAI 兼容服务',
  baseUrl: 'https://example.com/v1',
  apiKey: 'secret-key',
  modelName: 'gpt-4.1-mini',
  embeddingModelName: 'text-embedding-3-small',
  enabled: true,
  allowSensitiveFields: true,
);

void main() {
  test('private QA blocks when llm readiness is false', () async {
    final container = ProviderContainer(
      overrides: [
        localLlmReadinessProvider.overrideWith(
          (ref) async => const LocalLlmReadiness(
            ready: false,
            reason: '本地 LLM 当前不可用。',
            activeModel: null,
            runtimeState: null,
          ),
        ),
        externalProviderStatusProvider.overrideWith(
          (ref) async => const ExternalProviderStatus(
            available: false,
            reason: '尚未启用外部模型提供方。',
            config: null,
          ),
        ),
      ],
    );

    addTearDown(container.dispose);

    final orchestrator = container.read(aiChatOrchestratorProvider);

    await expectLater(
      () => orchestrator.send(
        const AiChatRequest(mode: ChatMode.privateQa, userInput: '帮我总结一下邮箱账号'),
      ),
      throwsA(
        predicate(
          (error) =>
              error is StateError && error.toString().contains('本地 LLM 当前不可用。'),
        ),
      ),
    );
  });

  test(
    'free chat defaults to local and never falls back when local llm is unavailable',
    () async {
      final fakeExternalClient = _FakeExternalProviderClient();
      final container = ProviderContainer(
        overrides: [
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: false,
              reason: '本地 LLM 当前不可用。',
              activeModel: null,
              runtimeState: null,
            ),
          ),
          externalProviderStatusProvider.overrideWith(
            (ref) async => const ExternalProviderStatus(
              available: true,
              reason: '外部模型已可用：OpenAI 兼容服务',
              config: _externalProvider,
            ),
          ),
          externalProviderClientRouterProvider.overrideWithValue(
            fakeExternalClient,
          ),
        ],
      );

      addTearDown(container.dispose);

      final orchestrator = container.read(aiChatOrchestratorProvider);
      await expectLater(
        () => orchestrator.send(
          const AiChatRequest(mode: ChatMode.freeChat, userInput: '你好，介绍一下你自己'),
        ),
        throwsA(
          predicate(
            (error) =>
                error is StateError &&
                error.toString().contains('本地 LLM 当前不可用。'),
          ),
        ),
      );

      expect(fakeExternalClient.lastPrompt, isNull);
      expect(fakeExternalClient.lastUsedPrivateContext, isNull);
    },
  );

  test(
    'free chat blocks external private context when provider policy forbids sensitive fields',
    () async {
      final fakeExternalClient = _FakeExternalProviderClient();
      final fakeRetriever = _FakeAiChatContextRetriever(
        items: const [
          ChatContextItem(
            id: 'secret-1',
            type: ChatContextItemType.secret,
            title: 'GitHub',
            preview: 'octo-user',
            summary: '账号：octo-user',
          ),
        ],
      );
      const blockedConfig = ExternalProviderConfig(
        id: 'provider-2',
        providerType: ExternalProviderType.openAiCompatible,
        displayName: 'OpenAI 兼容服务',
        baseUrl: 'https://example.com/v1',
        apiKey: 'secret-key',
        modelName: 'gpt-4.1-mini',
        embeddingModelName: 'text-embedding-3-small',
        enabled: true,
        allowSensitiveFields: false,
      );
      final container = ProviderContainer(
        overrides: [
          externalProviderConsentStoreProvider.overrideWithValue(
            _MemoryExternalProviderConsentStore(),
          ),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: false,
              reason: '本地 LLM 当前不可用。',
              activeModel: null,
              runtimeState: null,
            ),
          ),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: 'ready',
              activeEmbeddingModel: _embeddingModel,
            ),
          ),
          aiChatContextRetrieverProvider.overrideWithValue(fakeRetriever),
          externalProviderRepositoryProvider.overrideWithValue(
            _MemoryExternalProviderRepository(
              configs: const <ExternalProviderConfig>[blockedConfig],
            ),
          ),
          externalProviderClientRouterProvider.overrideWithValue(
            fakeExternalClient,
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults().copyWith(
              allowExternalProviderAccess: true,
            ),
          ),
        ],
      );

      addTearDown(container.dispose);

      final orchestrator = container.read(aiChatOrchestratorProvider);
      await container
          .read(externalPrivacyConfirmationControllerProvider)
          .markAcknowledged(blockedConfig, includesPrivateContext: true);

      await expectLater(
        () => orchestrator.send(
          const AiChatRequest(
            mode: ChatMode.freeChat,
            userInput: '帮我回忆 GitHub 登录信息',
            backendPreference: ChatBackendPreference.external,
            allowPrivateContext: true,
          ),
        ),
        throwsA(
          predicate(
            (error) =>
                error is ExternalChatGatewayException &&
                error.toString().contains('当前外部模型未允许访问私密内容'),
          ),
        ),
      );
    },
  );

  test(
    'private QA uses semantic retrieval before local llm generation',
    () async {
      final callLog = <String>[];
      final fakeRetriever = _FakeAiChatContextRetriever(
        onRetrieve: () => callLog.add('retrieve'),
        items: const [
          ChatContextItem(
            id: 'note-1',
            type: ChatContextItemType.note,
            title: '邮箱整理',
            preview: '正文预览',
            summary: '摘要：记录了主邮箱与备用邮箱。',
          ),
        ],
      );
      final fakeLlmEngine = _FakeLlmEngine(
        onGenerate: (request) => callLog.add('generate'),
      );

      final container = ProviderContainer(
        overrides: [
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: 'ready',
              activeEmbeddingModel: _embeddingModel,
            ),
          ),
          aiChatContextRetrieverProvider.overrideWithValue(fakeRetriever),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );

      addTearDown(container.dispose);

      final orchestrator = container.read(aiChatOrchestratorProvider);
      final response = await orchestrator.send(
        const AiChatRequest(mode: ChatMode.privateQa, userInput: '帮我总结一下邮箱账号'),
      );

      expect(callLog, ['retrieve', 'generate']);
      expect(fakeLlmEngine.lastRequest?.usedPrivateContext, isTrue);
      expect(fakeLlmEngine.lastRequest?.prompt, contains('摘要：记录了主邮箱与备用邮箱。'));
      expect(response.usedPrivateContext, isTrue);
      expect(response.sourceType, ChatContextSource.autoRetrieved);
      expect(response.contextSummary, ['摘要：记录了主邮箱与备用邮箱。']);
    },
  );

  test(
    'free chat can answer without private context when llm is ready',
    () async {
      final fakeRetriever = _FakeAiChatContextRetriever(
        onRetrieve: () =>
            fail('free chat pure mode should not retrieve private context'),
        items: const [],
      );
      final fakeLlmEngine = _FakeLlmEngine();

      final container = ProviderContainer(
        overrides: [
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          aiChatContextRetrieverProvider.overrideWithValue(fakeRetriever),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );

      addTearDown(container.dispose);

      final orchestrator = container.read(aiChatOrchestratorProvider);
      final response = await orchestrator.send(
        const AiChatRequest(mode: ChatMode.freeChat, userInput: '你好，介绍一下你自己'),
      );

      expect(fakeLlmEngine.lastRequest?.usedPrivateContext, isFalse);
      expect(response.usedPrivateContext, isFalse);
      expect(response.sourceType, ChatContextSource.none);
      expect(response.contextSummary, isEmpty);
    },
  );

  test(
    'free chat with allowPrivateContext=true can combine auto retrieval and manual items',
    () async {
      final fakeRetriever = _FakeAiChatContextRetriever(
        items: const [
          ChatContextItem(
            id: 'secret-1',
            type: ChatContextItemType.secret,
            title: 'GitHub',
            preview: 'octo-user',
            summary: '账号：octo-user',
          ),
        ],
      );
      final fakeLlmEngine = _FakeLlmEngine();

      final container = ProviderContainer(
        overrides: [
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: 'ready',
              activeEmbeddingModel: _embeddingModel,
            ),
          ),
          aiChatContextRetrieverProvider.overrideWithValue(fakeRetriever),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
          chatContextProjectorProvider.overrideWithValue(
            const _FakeChatContextProjector(<ProjectedChatContextItem>[
              ProjectedChatContextItem(
                type: ChatContextItemType.note,
                title: '开发备忘',
                content: '附注：MFA 已开启',
              ),
            ]),
          ),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );

      addTearDown(container.dispose);

      final orchestrator = container.read(aiChatOrchestratorProvider);
      final response = await orchestrator.send(
        const AiChatRequest(
          mode: ChatMode.freeChat,
          userInput: '帮我回忆 GitHub 登录信息',
          allowPrivateContext: true,
          manualItems: [
            ChatContextItem(
              id: 'note-1',
              type: ChatContextItemType.note,
              title: '开发备忘',
              preview: 'MFA 已开启',
              summary: '附注：MFA 已开启',
            ),
          ],
        ),
      );

      expect(fakeLlmEngine.lastRequest?.usedPrivateContext, isTrue);
      expect(fakeLlmEngine.lastRequest?.prompt, contains('账号：octo-user'));
      expect(fakeLlmEngine.lastRequest?.prompt, contains('附注：MFA 已开启'));
      expect(response.usedPrivateContext, isTrue);
      expect(response.sourceType, ChatContextSource.mixed);
      expect(response.contextSummary, ['账号：octo-user', '附注：MFA 已开启']);
    },
  );

  test(
    'controller persists user and assistant messages with session metadata after successful send',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _FakeLlmEngine();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.send('你好，继续聊天');

      expect(fakeRepository.savedSessions, hasLength(1));
      expect(fakeRepository.savedMessages, hasLength(2));
      expect(
        fakeRepository.savedMessages.first.role,
        ChatStoredMessageRole.user,
      );
      expect(
        fakeRepository.savedMessages.last.role,
        ChatStoredMessageRole.assistant,
      );
      expect(
        fakeRepository.savedMessages.last.status,
        ChatStoredMessageStatus.completed,
      );
      expect(
        fakeRepository.savedMessages.first.sessionId,
        fakeRepository.savedMessages.last.sessionId,
      );
      expect(fakeRepository.savedSessions.last.lastModelId, 'llm-1');
      expect(
        fakeRepository.savedMessages.last.backendUsage?.actualBackend,
        'llama.cpp',
      );
      expect(
        fakeRepository.savedMessages.last.backendUsage?.actualModel,
        'llm-1',
      );
      expect(
        fakeRepository.savedSessions.single.updatedAt.isAfter(
          fakeRepository.savedSessions.single.createdAt,
        ),
        isTrue,
      );
    },
  );

  test(
    'controller persists failed assistant-side message when generation fails',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _ThrowingLlmEngine();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.send('这次会失败');

      expect(fakeRepository.savedMessages, hasLength(2));
      expect(
        fakeRepository.savedMessages.last.role,
        ChatStoredMessageRole.system,
      );
      expect(
        fakeRepository.savedMessages.last.status,
        ChatStoredMessageStatus.failed,
      );
      expect(fakeRepository.savedSessions.single.lastModelId, isNull);
    },
  );

  test(
    'controller keeps failed assistant message persistence when runtime reports degraded generation',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _ThrowingLlmEngine(message: '真实本地 LLM 生成失败');
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.send('运行真实本地 LLM');

      expect(
        fakeRepository.savedMessages.last.role,
        ChatStoredMessageRole.system,
      );
      expect(
        fakeRepository.savedMessages.last.status,
        ChatStoredMessageStatus.failed,
      );
      expect(fakeRepository.savedMessages.last.content, '本地模型请求失败，请稍后重试。');
      expect(
        fakeRepository.savedMessages.last.content,
        isNot(contains('真实本地 LLM 生成失败')),
      );
    },
  );

  test(
    'controller creates paired user and assistant messages with shared correlation timestamp',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _FakeLlmEngine();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.send('你好，配对测试');

      expect(fakeRepository.savedMessages, hasLength(2));

      final userMessage = fakeRepository.savedMessages.firstWhere(
        (message) => message.role == ChatStoredMessageRole.user,
      );
      final assistantMessage = fakeRepository.savedMessages.firstWhere(
        (message) => message.role == ChatStoredMessageRole.assistant,
      );

      final userMicros = int.parse(userMessage.id.replaceFirst('user-', ''));
      final assistantMicros = int.parse(
        assistantMessage.id.replaceFirst('assistant-', ''),
      );

      expect(
        userMicros,
        equals(assistantMicros),
        reason:
            'user and assistant message IDs must share the same correlation timestamp',
      );
      expect(userMessage.sessionId, equals(assistantMessage.sessionId));
      expect(userMessage.createdAt.microsecondsSinceEpoch, equals(userMicros));
      expect(
        assistantMessage.createdAt.microsecondsSinceEpoch,
        greaterThanOrEqualTo(assistantMicros),
        reason:
            'assistant reply is created later but must preserve the original correlation id seed',
      );
    },
  );

  test(
    'controller sends only complete prior turns and preserves session creation time',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _FakeLlmEngine();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.send('FIRST_USER_TURN');
      final originalCreatedAt = fakeRepository.savedSessions.single.createdAt;

      await controller.send('SECOND_USER_TURN');

      expect(fakeLlmEngine.requests, hasLength(2));
      expect(fakeLlmEngine.requests.last.prompt, contains('FIRST_USER_TURN'));
      expect(fakeLlmEngine.requests.last.prompt, contains('普通回答'));
      expect(fakeLlmEngine.requests.last.prompt, contains('SECOND_USER_TURN'));
      expect(fakeRepository.savedSessions.single.createdAt, originalCreatedAt);
    },
  );

  test(
    'controller excludes failed and incomplete turns from history',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _FailThenSucceedLlmEngine();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.send('FAILED_USER_TURN');
      await controller.send('RECOVERY_USER_TURN');

      expect(fakeLlmEngine.requests, hasLength(2));
      expect(
        fakeLlmEngine.requests.last.prompt,
        isNot(contains('FAILED_USER_TURN')),
      );
      expect(fakeLlmEngine.requests.last.prompt, isNot(contains('本地模型请求失败')));
      expect(
        fakeLlmEngine.requests.last.prompt,
        contains('RECOVERY_USER_TURN'),
      );
    },
  );

  test(
    'controller starts a blank new session without restoring the latest old session',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final previousSession = ChatSession(
        id: 'session-old',
        mode: ChatMode.freeChat,
        title: '旧会话',
        allowPrivateContext: false,
        archived: false,
        createdAt: DateTime(2026, 5, 11, 19),
        updatedAt: DateTime(2026, 5, 11, 19, 10),
      );
      await fakeRepository.saveSession(previousSession);
      await fakeRepository.saveMessage(
        ChatStoredMessage(
          id: 'message-old',
          sessionId: previousSession.id,
          role: ChatStoredMessageRole.user,
          content: '旧消息',
          status: ChatStoredMessageStatus.completed,
          createdAt: previousSession.updatedAt,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.restoreSessionIfNeeded();
      expect(controller.state.currentSessionId, previousSession.id);
      expect(controller.state.messages.single.text, '旧消息');

      await controller.startNewSession();
      await controller.restoreSessionIfNeeded();

      expect(controller.state.currentSessionId, isNull);
      expect(controller.state.messages, isEmpty);
      expect(container.read(currentChatSessionIdProvider), isNull);
    },
  );

  test(
    'shared session providers stay blank after explicit new session',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final previousSession = ChatSession(
        id: 'session-old',
        mode: ChatMode.freeChat,
        title: '旧会话',
        allowPrivateContext: false,
        archived: false,
        createdAt: DateTime(2026, 5, 11, 20),
        updatedAt: DateTime(2026, 5, 11, 20, 10),
      );
      await fakeRepository.saveSession(previousSession);
      await fakeRepository.saveMessage(
        ChatStoredMessage(
          id: 'message-old',
          sessionId: previousSession.id,
          role: ChatStoredMessageRole.user,
          content: '旧消息',
          status: ChatStoredMessageStatus.completed,
          createdAt: previousSession.updatedAt,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.startNewSession();

      final currentSession = await container.read(
        currentChatSessionProvider.future,
      );
      final currentMessages = await container.read(
        currentChatMessagesProvider.future,
      );

      expect(currentSession, isNull);
      expect(currentMessages, isEmpty);
    },
  );
}

class _MemoryExternalProviderConsentStore
    implements ExternalProviderConsentStore {
  final Map<String, bool> _values = <String, bool>{};

  @override
  Future<bool> read(String key) async => _values[key] ?? false;

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> write(String key, bool value) async {
    _values[key] = value;
  }
}

class _FakeAiChatContextRetriever implements AiChatContextRetriever {
  _FakeAiChatContextRetriever({this.onRetrieve, required this.items});

  final void Function()? onRetrieve;
  final List<ChatContextItem> items;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required ModelRegistryEntry embeddingModel,
  }) async {
    onRetrieve?.call();
    return items;
  }
}

class _FakeChatContextProjector implements ChatContextProjector {
  const _FakeChatContextProjector(this.projectedItems);

  final List<ProjectedChatContextItem> projectedItems;

  @override
  Future<List<ProjectedChatContextItem>> projectManual({
    required List<ChatContextItem> items,
    required SearchConfiguration configuration,
    required ChatContextProjectionTarget target,
  }) async {
    return projectedItems;
  }
}

class _FakeLlmEngine implements LlmEngine {
  _FakeLlmEngine({this.onGenerate});

  final void Function(LlmInferenceRequest request)? onGenerate;
  LlmInferenceRequest? lastRequest;
  final List<LlmInferenceRequest> requests = <LlmInferenceRequest>[];

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    lastRequest = request;
    requests.add(request);
    onGenerate?.call(request);
    return LlmInferenceResponse(
      text: request.usedPrivateContext ? '结合私密上下文后的回答' : '普通回答',
      finishReason: 'stop',
      usedPrivateContext: request.usedPrivateContext,
    );
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) {
    throw UnimplementedError();
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _FailThenSucceedLlmEngine implements LlmEngine {
  final List<LlmInferenceRequest> requests = <LlmInferenceRequest>[];

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    requests.add(request);
    if (requests.length == 1) {
      throw StateError('RAW_FAILURE_SENTINEL');
    }
    return LlmInferenceResponse(
      text: 'recovered',
      finishReason: 'stop',
      usedPrivateContext: request.usedPrivateContext,
    );
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) {
    throw UnimplementedError();
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _ThrowingLlmEngine implements LlmEngine {
  _ThrowingLlmEngine({this.message = 'generation failed'});

  final String message;

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    throw StateError(message);
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) {
    throw UnimplementedError();
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _FakeExternalProviderClient implements ExternalProviderClient {
  String? lastPrompt;
  bool? lastUsedPrivateContext;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    lastPrompt = prompt;
    lastUsedPrivateContext = usedPrivateContext;
    return '来自外部模型的回答';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
}

class _FakeChatSessionRepository implements ChatSessionRepository {
  final List<ChatSession> savedSessions = <ChatSession>[];
  final List<ChatStoredMessage> savedMessages = <ChatStoredMessage>[];

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    return savedSessions
        .where((session) => session.id == sessionId)
        .firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    return savedMessages
        .where((message) => message.sessionId == sessionId)
        .toList(growable: false);
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    final sorted = List<ChatSession>.from(savedSessions)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {
    savedMessages.removeWhere((item) => item.id == message.id);
    savedMessages.add(message);
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    savedSessions.removeWhere((item) => item.id == session.id);
    savedSessions.add(session);
  }
}

class _MemoryExternalProviderRepository implements ExternalProviderRepository {
  _MemoryExternalProviderRepository({
    List<ExternalProviderConfig> configs = const <ExternalProviderConfig>[],
  }) : _configs = List<ExternalProviderConfig>.from(configs);

  final List<ExternalProviderConfig> _configs;

  @override
  Future<List<ExternalProviderConfig>> loadAll() async {
    return List<ExternalProviderConfig>.from(_configs);
  }

  @override
  Future<ExternalProviderConfig?> loadById(String id) async {
    return _configs.where((config) => config.id == id).firstOrNull;
  }

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    return _configs.where((config) => config.enabled).firstOrNull;
  }

  @override
  Future<void> save(ExternalProviderConfig config) async {
    _configs.removeWhere((item) => item.id == config.id);
    _configs.add(config);
  }
}
