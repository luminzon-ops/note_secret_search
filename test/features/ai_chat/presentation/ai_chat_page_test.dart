import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> buildContainer({
    LocalLlmReadiness? llmReadiness,
    SemanticSearchReadiness? semanticReadiness,
    ChatSessionRepository? chatRepository,
    ExternalProviderStatus? externalStatus,
    List<Override> extraOverrides = const <Override>[],
  }) async {
    return ProviderContainer(
      overrides: [
        localLlmReadinessProvider.overrideWith(
          (ref) async =>
              llmReadiness ??
              const LocalLlmReadiness(
                ready: true,
                reason: 'ready',
                activeModel: null,
                runtimeState: LlmRuntimeState(
                  ready: true,
                  reason: 'ready',
                  status: LlmRuntimeStatus.ready,
                ),
              ),
        ),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async =>
              semanticReadiness ??
              const SemanticSearchReadiness(
                ready: true,
                reason: 'ready',
              ),
        ),
        externalProviderStatusProvider.overrideWith(
          (ref) async =>
              externalStatus ??
              const ExternalProviderStatus(
                available: false,
                reason: '尚未启用外部模型提供方。',
                config: null,
              ),
        ),
        chatSessionRepositoryProvider.overrideWithValue(
          chatRepository ?? const _FakeChatSessionRepository(),
        ),
        ...extraOverrides,
      ],
    );
  }

  Future<void> pumpChatRouteAtSize(
    WidgetTester tester,
    ProviderContainer container, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AI chat page uses drawer-based recent sessions on phone widths', (tester) async {
    final container = await buildContainer(
      chatRepository: _FakeChatSessionRepository(
        sessions: [
          ChatSession(
            id: 'session-1',
            mode: ChatMode.privateQa,
            title: '邮箱问答',
            allowPrivateContext: true,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
        ],
      ),
    );

    addTearDown(container.dispose);

    await pumpChatRouteAtSize(tester, container, size: const Size(393, 852));

    expect(find.text('最近会话'), findsNothing);
    expect(find.byTooltip('打开最近会话'), findsOneWidget);

    await tester.tap(find.byTooltip('打开最近会话'));
    await tester.pumpAndSettle();

    expect(find.text('最近会话'), findsOneWidget);
    expect(find.text('邮箱问答'), findsOneWidget);
  });

  testWidgets('AI chat page keeps persistent recent sessions sidebar on wide widths', (tester) async {
    final container = await buildContainer(
      chatRepository: _FakeChatSessionRepository(
        sessions: [
          ChatSession(
            id: 'session-1',
            mode: ChatMode.privateQa,
            title: '邮箱问答',
            allowPrivateContext: true,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
        ],
      ),
    );

    addTearDown(container.dispose);

    await pumpChatRouteAtSize(tester, container, size: const Size(1280, 800));

    expect(find.text('最近会话'), findsOneWidget);
    expect(find.byTooltip('打开最近会话'), findsNothing);
  });

  testWidgets('App shell shows 问答 navigation destination on AI chat route', (tester) async {
    final container = await buildContainer();

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('问答'), findsOneWidget);
  });

  testWidgets('AI chat route renders 私密内容问答 and 自由聊天 tabs', (tester) async {
    final container = await buildContainer();

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('私密内容问答'), findsOneWidget);
    expect(find.text('自由聊天'), findsOneWidget);
  });

  testWidgets('AI chat page shows jump-to-model-management CTA when llm is unavailable', (tester) async {
    final container = await buildContainer(
      llmReadiness: const LocalLlmReadiness(
        ready: false,
        reason: '尚未选择本地 LLM 模型。',
        activeModel: null,
        runtimeState: null,
      ),
      semanticReadiness: const SemanticSearchReadiness(
        ready: false,
        reason: '本地语义检索不可用。',
        runtimeStatus: EmbeddingRuntimeStatus.degraded,
      ),
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('前往模型管理'), findsOneWidget);
  });

  testWidgets('AI chat page shows external provider banner when local llm is unavailable but external provider is ready', (
    tester,
  ) async {
    final container = await buildContainer(
      llmReadiness: const LocalLlmReadiness(
        ready: false,
        reason: '尚未选择本地 LLM 模型。',
        activeModel: null,
        runtimeState: null,
      ),
      semanticReadiness: const SemanticSearchReadiness(
        ready: false,
        reason: '本地语义检索不可用。',
        runtimeStatus: EmbeddingRuntimeStatus.degraded,
      ),
      externalStatus: const ExternalProviderStatus(
        available: true,
        reason: '外部模型已可用：OpenAI 兼容服务',
        config: ExternalProviderConfig(
          id: 'provider-1',
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
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('外部模型已可用：OpenAI 兼容服务'), findsOneWidget);
    expect(find.text('前往模型管理'), findsNothing);
  });

  testWidgets('free chat tab exposes allow private context toggle', (tester) async {
    final container = await buildContainer();

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('自由聊天'));
    await tester.pumpAndSettle();

    expect(find.text('允许参考私密内容'), findsOneWidget);
  });

  testWidgets('AI chat page lists existing sessions and can switch between them', (tester) async {
    final container = await buildContainer(
      chatRepository: _FakeChatSessionRepository(
        sessions: [
          ChatSession(
            id: 'session-1',
            mode: ChatMode.privateQa,
            title: '邮箱问答',
            allowPrivateContext: true,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
          ChatSession(
            id: 'session-2',
            mode: ChatMode.freeChat,
            title: '自由对话',
            allowPrivateContext: false,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(4000),
          ),
        ],
        messagesBySession: {
          'session-1': [
            ChatStoredMessage(
              id: 'm1',
              sessionId: 'session-1',
              role: ChatStoredMessageRole.user,
              content: '邮箱历史',
              status: ChatStoredMessageStatus.completed,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ],
          'session-2': [
            ChatStoredMessage(
              id: 'm2',
              sessionId: 'session-2',
              role: ChatStoredMessageRole.user,
              content: '自由聊天历史',
              status: ChatStoredMessageStatus.completed,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ],
        },
      ),
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('最近会话'), findsOneWidget);
    expect(find.text('邮箱问答'), findsOneWidget);
    expect(find.text('自由对话'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, '自由对话'));
    await tester.pumpAndSettle();

    expect(container.read(currentChatSessionIdProvider), 'session-2');
  });

  testWidgets('AI chat page exposes new session entry in session panel', (tester) async {
    final container = await buildContainer(
      chatRepository: _FakeChatSessionRepository(
        sessions: [
          ChatSession(
            id: 'session-1',
            mode: ChatMode.freeChat,
            title: '自由对话',
            allowPrivateContext: false,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
        ],
      ),
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await container.read(chatSessionControllerProvider).selectSession('session-1');
    await tester.pumpAndSettle();

    expect(container.read(currentChatSessionIdProvider), 'session-1');
    expect(find.text('新建会话'), findsOneWidget);

    await tester.tap(find.text('新建会话'));
    await tester.pumpAndSettle();

    expect(container.read(currentChatSessionIdProvider), isNull);
    expect(await container.read(currentChatSessionProvider.future), isNull);
  });

  testWidgets('AI chat page can reopen an old session after starting a new session', (tester) async {
    final container = await buildContainer(
      chatRepository: _FakeChatSessionRepository(
        sessions: [
          ChatSession(
            id: 'session-1',
            mode: ChatMode.freeChat,
            title: '自由对话',
            allowPrivateContext: false,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
        ],
        messagesBySession: {
          'session-1': [
            ChatStoredMessage(
              id: 'm1',
              sessionId: 'session-1',
              role: ChatStoredMessageRole.user,
              content: '旧会话消息',
              status: ChatStoredMessageStatus.completed,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ],
        },
      ),
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('自由聊天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建会话'));
    await tester.pumpAndSettle();

    expect(container.read(freeChatControllerProvider).messages, isEmpty);

    await tester.tap(find.text('自由对话'));
    await tester.pumpAndSettle();

    expect(container.read(currentChatSessionIdProvider), 'session-1');
    expect(container.read(freeChatControllerProvider).currentSessionId, 'session-1');
    expect(container.read(freeChatControllerProvider).messages.single.text, '旧会话消息');
    expect(find.text('旧会话消息'), findsOneWidget);
  });

  testWidgets('free chat renders first local response after sending a message', (tester) async {
    final fakeLlmEngine = _RecordingLlmEngine(responseText: '这是本地首轮回答。');
    final container = await buildContainer(
      llmReadiness: const LocalLlmReadiness(
        ready: true,
        reason: '本地 LLM 模型已就绪：Qwen Local',
        activeModel: _localLlmModel,
        runtimeState: LlmRuntimeState(
          ready: true,
          reason: '本地 LLM 模型已就绪：Qwen Local',
          status: LlmRuntimeStatus.ready,
        ),
      ),
      extraOverrides: [llmEngineProvider.overrideWithValue(fakeLlmEngine)],
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('自由聊天'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '你好，本地模型');
    await tester.tap(find.widgetWithText(FilledButton, '发送').last);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('你好，本地模型'), findsOneWidget);
    expect(find.text('这是本地首轮回答。'), findsOneWidget);
    expect(fakeLlmEngine.lastRequest, isNotNull);
    expect(fakeLlmEngine.lastRequest?.model.id, 'llm-local');
    expect(fakeLlmEngine.lastRequest?.prompt, '你好，本地模型');
    expect(fakeLlmEngine.lastRequest?.usedPrivateContext, isFalse);
  });

  testWidgets('free chat asks for confirmation before sending private context to external provider', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = await buildContainer(
      llmReadiness: const LocalLlmReadiness(
        ready: false,
        reason: '尚未选择本地 LLM 模型。',
        activeModel: null,
        runtimeState: null,
      ),
      semanticReadiness: const SemanticSearchReadiness(
        ready: true,
        reason: 'ready',
        activeEmbeddingModel: _embeddingModel,
      ),
      externalStatus: const ExternalProviderStatus(
        available: true,
        reason: '外部模型已可用：OpenAI 兼容服务',
        config: ExternalProviderConfig(
          id: 'provider-1',
          providerType: ExternalProviderType.openAiCompatible,
          displayName: 'OpenAI 兼容服务',
          baseUrl: 'https://example.com/v1',
          apiKey: 'secret-key',
          modelName: 'gpt-4.1-mini',
          embeddingModelName: 'text-embedding-3-small',
          enabled: true,
          allowSensitiveFields: true,
        ),
      ),
      extraOverrides: [
        aiChatContextRetrieverProvider.overrideWithValue(
          const _StaticContextRetriever(
            items: [
              ChatContextItem(
                id: 'secret-1',
                type: ChatContextItemType.secret,
                title: 'GitHub',
                preview: 'octo-user',
                summary: '账号：octo-user',
              ),
            ],
          ),
        ),
        externalProviderClientProvider.overrideWithValue(_ImmediateExternalProviderClient()),
      ],
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('自由聊天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许参考私密内容'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '帮我回忆 GitHub 登录信息');
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('你即将把私密内容发送到外部模型'), findsOneWidget);
  });

  testWidgets('private QA asks for confirmation before sending externally retrieved private context', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = await buildContainer(
      llmReadiness: const LocalLlmReadiness(
        ready: false,
        reason: '尚未选择本地 LLM 模型。',
        activeModel: null,
        runtimeState: null,
      ),
      semanticReadiness: const SemanticSearchReadiness(
        ready: true,
        reason: 'ready',
        activeEmbeddingModel: _embeddingModel,
      ),
      externalStatus: const ExternalProviderStatus(
        available: true,
        reason: '外部模型已可用：OpenAI 兼容服务',
        config: ExternalProviderConfig(
          id: 'provider-1',
          providerType: ExternalProviderType.openAiCompatible,
          displayName: 'OpenAI 兼容服务',
          baseUrl: 'https://example.com/v1',
          apiKey: 'secret-key',
          modelName: 'gpt-4.1-mini',
          embeddingModelName: 'text-embedding-3-small',
          enabled: true,
          allowSensitiveFields: true,
        ),
      ),
      extraOverrides: [
        aiChatContextRetrieverProvider.overrideWithValue(
          const _StaticContextRetriever(
            items: [
              ChatContextItem(
                id: 'note-1',
                type: ChatContextItemType.note,
                title: '邮箱整理',
                preview: '正文预览',
                summary: '摘要：记录了主邮箱与备用邮箱。',
              ),
            ],
          ),
        ),
        externalProviderClientProvider.overrideWithValue(_ImmediateExternalProviderClient()),
      ],
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '帮我总结邮箱账号');
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('你即将把私密内容发送到外部模型'), findsOneWidget);
  });

  testWidgets('acknowledged external provider does not prompt again for private-context send', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ai.external_privacy_ack.provider-1': true,
    });
    final container = await buildContainer(
      llmReadiness: const LocalLlmReadiness(
        ready: false,
        reason: '尚未选择本地 LLM 模型。',
        activeModel: null,
        runtimeState: null,
      ),
      semanticReadiness: const SemanticSearchReadiness(
        ready: true,
        reason: 'ready',
        activeEmbeddingModel: _embeddingModel,
      ),
      externalStatus: const ExternalProviderStatus(
        available: true,
        reason: '外部模型已可用：OpenAI 兼容服务',
        config: ExternalProviderConfig(
          id: 'provider-1',
          providerType: ExternalProviderType.openAiCompatible,
          displayName: 'OpenAI 兼容服务',
          baseUrl: 'https://example.com/v1',
          apiKey: 'secret-key',
          modelName: 'gpt-4.1-mini',
          embeddingModelName: 'text-embedding-3-small',
          enabled: true,
          allowSensitiveFields: true,
        ),
      ),
      extraOverrides: [
        aiChatContextRetrieverProvider.overrideWithValue(
          const _StaticContextRetriever(
            items: [
              ChatContextItem(
                id: 'secret-1',
                type: ChatContextItemType.secret,
                title: 'GitHub',
                preview: 'octo-user',
                summary: '账号：octo-user',
              ),
            ],
          ),
        ),
        externalProviderClientProvider.overrideWithValue(_ImmediateExternalProviderClient()),
      ],
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('自由聊天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许参考私密内容'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '帮我回忆 GitHub 登录信息');
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('你即将把私密内容发送到外部模型'), findsNothing);
  });
}

const _embeddingModel = ModelRegistryEntry(
  id: 'embed-1',
  type: 'embedding',
  provider: 'builtin',
  name: 'MiniLM Embedding',
  version: '1.0.0',
  sizeBytes: 10485760,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'mvp',
  localPath: '/data/models/minilm.onnx',
  checksum: 'embedding-checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _localLlmModel = ModelRegistryEntry(
  id: 'llm-local',
  type: 'llm',
  provider: 'builtin',
  name: 'Qwen Local',
  version: '1.0.0',
  sizeBytes: 1024,
  quantization: 'Q4_K_M',
  minRamMb: 2048,
  recommendedTier: 'mvp',
  localPath: '/data/models/qwen.gguf',
  checksum: 'llm-checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

class _FakeChatSessionRepository implements ChatSessionRepository {
  const _FakeChatSessionRepository({
    this.sessions = const <ChatSession>[],
    this.messagesBySession = const <String, List<ChatStoredMessage>>{},
  });

  final List<ChatSession> sessions;
  final Map<String, List<ChatStoredMessage>> messagesBySession;

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    return sessions.where((session) => session.id == sessionId).firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    return messagesBySession[sessionId] ?? const <ChatStoredMessage>[];
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    final sorted = List<ChatSession>.from(sessions)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {}

  @override
  Future<void> saveSession(ChatSession session) async {}
}

class _ImmediateExternalProviderClient implements ExternalProviderClient {
  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    return '来自外部模型的回答';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
}

class _StaticContextRetriever implements AiChatContextRetriever {
  const _StaticContextRetriever({required this.items});

  final List<ChatContextItem> items;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required ModelRegistryEntry embeddingModel,
  }) async {
    return items;
  }
}

class _RecordingLlmEngine implements LlmEngine {
  _RecordingLlmEngine({required this.responseText});

  final String responseText;
  LlmInferenceRequest? lastRequest;

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    lastRequest = request;
    return LlmInferenceResponse(
      text: responseText,
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
