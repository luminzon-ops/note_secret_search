import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/presentation/ai_chat_page.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

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
  checksum: 'embedding-checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

void main() {
  const defaultExternalStatus = ExternalProviderStatus(
    available: false,
    reason: '尚未启用外部模型提供方。',
    config: null,
  );

  Future<void> pumpChatPage(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: AiChatPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('private QA tab disables send when semantic readiness is false', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        localLlmReadinessProvider.overrideWith(
          (ref) async => const LocalLlmReadiness(
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
          (ref) async => const SemanticSearchReadiness(
            ready: false,
            reason: '尚未选择本地 embedding 模型。',
          ),
        ),
        externalProviderStatusProvider.overrideWith(
          (ref) async => defaultExternalStatus,
        ),
        chatSessionRepositoryProvider.overrideWithValue(
          const _FakeChatSessionRepository(),
        ),
      ],
    );

    addTearDown(container.dispose);

    await pumpChatPage(tester, container);

    expect(find.text('尚未选择本地 embedding 模型。'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '发送').first,
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('free chat tab allows send when llm is ready', (tester) async {
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        localLlmReadinessProvider.overrideWith(
          (ref) async => const LocalLlmReadiness(
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
          (ref) async => const SemanticSearchReadiness(
            ready: true,
            reason: 'semantic ready',
            activeEmbeddingModel: _embeddingModel,
          ),
        ),
        externalProviderStatusProvider.overrideWith(
          (ref) async => defaultExternalStatus,
        ),
        chatSessionRepositoryProvider.overrideWithValue(
          const _FakeChatSessionRepository(),
        ),
      ],
    );

    addTearDown(container.dispose);

    await pumpChatPage(tester, container);
    await tester.tap(find.text('自由聊天'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '发送').first,
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
    'free chat shows manual context entry point when private context is enabled',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
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
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: 'semantic ready',
              activeEmbeddingModel: _embeddingModel,
            ),
          ),
          externalProviderStatusProvider.overrideWith(
            (ref) async => defaultExternalStatus,
          ),
          chatSessionRepositoryProvider.overrideWithValue(
            const _FakeChatSessionRepository(),
          ),
        ],
      );

      addTearDown(container.dispose);

      await pumpChatPage(tester, container);
      await tester.tap(find.text('自由聊天'));
      await tester.pumpAndSettle();

      expect(find.text('手动选择私密内容'), findsNothing);

      await tester.tap(find.text('允许参考私密内容'));
      await tester.pump();

      expect(find.text('手动选择私密内容'), findsOneWidget);
    },
  );

  testWidgets(
    'manual picker remains usable when semantic readiness is false but llm is ready',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
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
            (ref) async => const SemanticSearchReadiness(
              ready: false,
              reason: '尚未选择本地 embedding 模型。',
            ),
          ),
          externalProviderStatusProvider.overrideWith(
            (ref) async => defaultExternalStatus,
          ),
          chatSessionRepositoryProvider.overrideWithValue(
            const _FakeChatSessionRepository(),
          ),
        ],
      );

      addTearDown(container.dispose);

      await pumpChatPage(tester, container);
      await tester.tap(find.text('自由聊天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('允许参考私密内容'));
      await tester.pump();

      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '手动选择私密内容'),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'private QA send action is disabled when semantic readiness is false',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
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
            (ref) async => const SemanticSearchReadiness(
              ready: false,
              reason: '本地语义检索当前不可用。',
            ),
          ),
          externalProviderStatusProvider.overrideWith(
            (ref) async => defaultExternalStatus,
          ),
          chatSessionRepositoryProvider.overrideWithValue(
            const _FakeChatSessionRepository(),
          ),
        ],
      );

      addTearDown(container.dispose);

      await pumpChatPage(tester, container);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '发送').first,
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'free chat requires fresh consent when external context becomes private',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final externalClient = _RecordingExternalProviderClient();
      const externalConfig = ExternalProviderConfig(
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
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          sharedPreferencesProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: false,
              reason: '尚未选择本地 LLM 模型。',
              activeModel: null,
              runtimeState: null,
            ),
          ),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: 'semantic ready',
              activeEmbeddingModel: _embeddingModel,
            ),
          ),
          externalProviderStatusProvider.overrideWith(
            (ref) async => const ExternalProviderStatus(
              available: true,
              reason: '外部模型已可用：OpenAI 兼容服务',
              config: externalConfig,
            ),
          ),
          externalProviderRepositoryProvider.overrideWithValue(
            _MemoryExternalProviderRepository(configs: [externalConfig]),
          ),
          externalProviderClientRouterProvider.overrideWithValue(
            externalClient,
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults().copyWith(
              allowExternalProviderAccess: true,
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(
            const _FakeChatSessionRepository(),
          ),
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
        ],
      );

      addTearDown(container.dispose);

      await pumpChatPage(tester, container);
      await tester.tap(find.text('自由聊天'));
      await tester.pumpAndSettle();

      final selector = find.byKey(const ValueKey('free-chat-backend-selector'));
      expect(selector, findsOneWidget);
      expect(
        container.read(freeChatControllerProvider).backendPreference,
        ChatBackendPreference.local,
      );
      await tester.tap(
        find.descendant(of: selector, matching: find.text('外部')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(freeChatControllerProvider).backendPreference,
        ChatBackendPreference.external,
      );

      await tester.enterText(find.byType(TextField).last, '普通外部问题');
      await tester.tap(find.widgetWithText(FilledButton, '发送').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('确认使用外部模型'), findsOneWidget);
      expect(find.text('提供商：OpenAI 兼容接口'), findsOneWidget);
      expect(find.text('Endpoint：https://example.com/v1'), findsOneWidget);
      expect(find.text('模型：gpt-4.1-mini'), findsOneWidget);
      expect(find.text('包含私密上下文：否'), findsOneWidget);
      expect(find.textContaining('secret-key'), findsNothing);
      expect(externalClient.generateCallCount, 0);

      await tester.tap(find.text('继续发送'));
      await tester.pumpAndSettle();
      expect(externalClient.generateCallCount, 1);
      expect(externalClient.lastUsedPrivateContext, isFalse);

      await tester.tap(find.text('允许参考私密内容'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '帮我回忆 GitHub 登录信息');
      await tester.tap(find.widgetWithText(FilledButton, '发送').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('确认使用外部模型'), findsOneWidget);
      expect(find.text('包含私密上下文：是'), findsOneWidget);
      expect(externalClient.generateCallCount, 1);

      await tester.tap(find.text('继续发送'));
      await tester.pumpAndSettle();

      expect(externalClient.generateCallCount, 2);
      expect(externalClient.lastUsedPrivateContext, isTrue);
    },
  );
}

class _FakeChatSessionRepository implements ChatSessionRepository {
  const _FakeChatSessionRepository();

  @override
  Future<ChatSession?> getSession(String sessionId) async => null;

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async =>
      const <ChatStoredMessage>[];

  @override
  Future<List<ChatSession>> listSessions() async => const <ChatSession>[];

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {}

  @override
  Future<void> saveSession(ChatSession session) async {}
}

class _RecordingExternalProviderClient implements ExternalProviderClient {
  int generateCallCount = 0;
  bool? lastUsedPrivateContext;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    generateCallCount++;
    lastUsedPrivateContext = usedPrivateContext;
    return '外部回复';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
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

class _StaticContextRetriever implements AiChatContextRetriever {
  const _StaticContextRetriever({required this.items});

  final List<ChatContextItem> items;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required dynamic embeddingModel,
  }) async {
    return items;
  }
}
