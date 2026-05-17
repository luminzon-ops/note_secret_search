import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_message.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

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
          (error) => error is StateError && error.toString().contains('本地 LLM 当前不可用。'),
        ),
      ),
    );
  });

  test('free chat falls back to external provider when local llm is unavailable', () async {
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
        externalProviderClientProvider.overrideWithValue(fakeExternalClient),
      ],
    );

    addTearDown(container.dispose);

    final orchestrator = container.read(aiChatOrchestratorProvider);
    final response = await orchestrator.send(
      const AiChatRequest(mode: ChatMode.freeChat, userInput: '你好，介绍一下你自己'),
    );

    expect(fakeExternalClient.lastPrompt, '你好，介绍一下你自己');
    expect(fakeExternalClient.lastUsedPrivateContext, isFalse);
    expect(response.text, '来自外部模型的回答');
  });

  test('free chat blocks external private context when provider policy forbids sensitive fields', () async {
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
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(
            ready: true,
            reason: 'ready',
            activeEmbeddingModel: _embeddingModel,
          ),
        ),
        aiChatContextRetrieverProvider.overrideWithValue(fakeRetriever),
        externalProviderStatusProvider.overrideWith(
          (ref) async => const ExternalProviderStatus(
            available: true,
            reason: '外部模型已可用：OpenAI 兼容服务',
            config: ExternalProviderConfig(
              id: 'provider-2',
              providerType: ExternalProviderType.openAiCompatible,
              displayName: 'OpenAI 兼容服务',
              baseUrl: 'https://example.com/v1',
              apiKey: 'secret-key',
              modelName: 'gpt-4.1-mini',
              embeddingModelName: 'text-embedding-3-small',
              enabled: true,
              allowSensitiveFields: false,
            ),
          ),
        ),
        externalProviderClientProvider.overrideWithValue(fakeExternalClient),
      ],
    );

    addTearDown(container.dispose);

    final orchestrator = container.read(aiChatOrchestratorProvider);

    await expectLater(
      () => orchestrator.send(
        const AiChatRequest(
          mode: ChatMode.freeChat,
          userInput: '帮我回忆 GitHub 登录信息',
          allowPrivateContext: true,
        ),
      ),
      throwsA(
        predicate(
          (error) => error is StateError && error.toString().contains('当前外部模型未允许访问私密内容'),
        ),
      ),
    );
  });

  test('private QA uses semantic retrieval before local llm generation', () async {
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
  });

  test('free chat can answer without private context when llm is ready', () async {
    final fakeRetriever = _FakeAiChatContextRetriever(
      onRetrieve: () => fail('free chat pure mode should not retrieve private context'),
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
  });

  test('free chat with allowPrivateContext=true can combine auto retrieval and manual items', () async {
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
  });

  test('controller persists user and assistant messages with session metadata after successful send', () async {
    final fakeRepository = _FakeChatSessionRepository();
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
        chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        llmEngineProvider.overrideWithValue(fakeLlmEngine),
      ],
    );

    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.send('你好，继续聊天');

    expect(fakeRepository.savedSessions, hasLength(1));
    expect(fakeRepository.savedMessages, hasLength(2));
    expect(fakeRepository.savedMessages.first.role, ChatStoredMessageRole.user);
    expect(fakeRepository.savedMessages.last.role, ChatStoredMessageRole.assistant);
    expect(fakeRepository.savedMessages.last.status, ChatStoredMessageStatus.completed);
    expect(fakeRepository.savedMessages.first.sessionId, fakeRepository.savedMessages.last.sessionId);
    expect(fakeRepository.savedSessions.last.lastModelId, 'llm-1');
    expect(fakeRepository.savedSessions.single.updatedAt.isAfter(fakeRepository.savedSessions.single.createdAt), isTrue);
  });

  test('controller persists failed assistant-side message when generation fails', () async {
    final fakeRepository = _FakeChatSessionRepository();
    final fakeLlmEngine = _ThrowingLlmEngine();
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
        chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        llmEngineProvider.overrideWithValue(fakeLlmEngine),
      ],
    );

    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.send('这次会失败');

    expect(fakeRepository.savedMessages, hasLength(2));
    expect(fakeRepository.savedMessages.last.role, ChatStoredMessageRole.system);
    expect(fakeRepository.savedMessages.last.status, ChatStoredMessageStatus.failed);
  });

  test('controller keeps failed assistant message persistence when runtime reports degraded generation', () async {
    final fakeRepository = _FakeChatSessionRepository();
    final fakeLlmEngine = _ThrowingLlmEngine(message: '真实本地 LLM 生成失败');
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
        chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        llmEngineProvider.overrideWithValue(fakeLlmEngine),
      ],
    );

    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.send('运行真实本地 LLM');

    expect(fakeRepository.savedMessages.last.role, ChatStoredMessageRole.system);
    expect(fakeRepository.savedMessages.last.status, ChatStoredMessageStatus.failed);
    expect(fakeRepository.savedMessages.last.content, contains('真实本地 LLM 生成失败'));
  });

  test('controller creates paired user and assistant messages with shared correlation timestamp', () async {
    final fakeRepository = _FakeChatSessionRepository();
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
      reason: 'user and assistant message IDs must share the same correlation timestamp',
    );
    expect(userMessage.sessionId, equals(assistantMessage.sessionId));
    expect(userMessage.createdAt.microsecondsSinceEpoch, equals(userMicros));
    expect(
      assistantMessage.createdAt.microsecondsSinceEpoch,
      greaterThanOrEqualTo(assistantMicros),
      reason: 'assistant reply is created later but must preserve the original correlation id seed',
    );
  });

  test('controller preserves user message when in-flight send state is reloaded before assistant reply returns', () async {
    final fakeRepository = _FakeChatSessionRepository();
    final fakeLlmEngine = _ControllableLlmEngine();
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
        chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        llmEngineProvider.overrideWithValue(fakeLlmEngine),
      ],
    );

    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    final sendFuture = controller.send('你好');

    await fakeLlmEngine.waitUntilRequested();

    final sessionId = controller.state.currentSessionId;
    expect(sessionId, isNotNull);

    await controller.selectSession(sessionId!);
    expect(controller.state.messages, hasLength(1));
    expect(controller.state.messages.single.role, ChatMessageRole.user);
    expect(controller.state.messages.single.text, '你好');

    fakeLlmEngine.completeWith(
      const LlmInferenceResponse(
        text: '普通回答',
        finishReason: 'stop',
        usedPrivateContext: false,
      ),
    );

    await sendFuture;

    expect(controller.state.messages, hasLength(2));
    expect(controller.state.messages[0].role, ChatMessageRole.user);
    expect(controller.state.messages[0].text, '你好');
    expect(controller.state.messages[1].role, ChatMessageRole.assistant);
    expect(controller.state.messages[1].text, '普通回答');
  });

  test('controller starts a blank new session without restoring the latest old session', () async {
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
  });

  test('shared session providers stay blank after explicit new session', () async {
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
        chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
      ],
    );

    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.startNewSession();

    final currentSession = await container.read(currentChatSessionProvider.future);
    final currentMessages = await container.read(currentChatMessagesProvider.future);

    expect(currentSession, isNull);
    expect(currentMessages, isEmpty);
  });
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

class _FakeLlmEngine implements LlmEngine {
  _FakeLlmEngine({this.onGenerate});

  final void Function(LlmInferenceRequest request)? onGenerate;
  LlmInferenceRequest? lastRequest;

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    lastRequest = request;
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

class _ControllableLlmEngine implements LlmEngine {
  final Completer<void> _requested = Completer<void>();
  final Completer<LlmInferenceResponse> _response = Completer<LlmInferenceResponse>();

  LlmInferenceRequest? lastRequest;

  Future<void> waitUntilRequested() => _requested.future;

  void completeWith(LlmInferenceResponse response) {
    if (!_response.isCompleted) {
      _response.complete(response);
    }
  }

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    lastRequest = request;
    if (!_requested.isCompleted) {
      _requested.complete();
    }
    return _response.future;
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
    return savedSessions.where((session) => session.id == sessionId).firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    return savedMessages.where((message) => message.sessionId == sessionId).toList(growable: false);
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
