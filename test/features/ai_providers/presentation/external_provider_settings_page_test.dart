import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/router/app_router.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/ai_providers/presentation/external_provider_settings_page.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';

void main() {
  testWidgets('settings page exposes external provider entry and route renders config page', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
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
            ready: false,
            reason: '尚未选择本地 embedding 模型。',
          ),
        ),
        chatSessionRepositoryProvider.overrideWithValue(const _FakeChatSessionRepository()),
        externalProviderRepositoryProvider.overrideWithValue(_MemoryExternalProviderRepository()),
        externalProviderClientProvider.overrideWithValue(_RecordingExternalProviderClient()),
      ],
    );

    final router = container.read(appRouterProvider);
    router.go('/settings');

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('外部模型'), findsOneWidget);
    await tester.tap(find.text('外部模型'));
    await tester.pumpAndSettle();

    expect(find.text('外部模型配置'), findsOneWidget);
    expect(find.text('OpenAI 兼容接口'), findsOneWidget);
  });

  testWidgets('external provider settings page renders form and tests connection', (tester) async {
    final repository = _MemoryExternalProviderRepository();
    final client = _RecordingExternalProviderClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          externalProviderRepositoryProvider.overrideWithValue(repository),
          externalProviderClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Placeholder()),
        ),
      ),
    );

    final context = tester.element(find.byType(Placeholder));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ExternalProviderSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, '配置名称'), '我的 OpenAI 兼容服务');
    await tester.enterText(find.widgetWithText(TextFormField, 'Base URL'), 'https://example.com/v1');
    await tester.enterText(find.widgetWithText(TextFormField, 'API Key'), 'secret-key');
    await tester.enterText(find.widgetWithText(TextFormField, '聊天模型'), 'gpt-4.1-mini');
    await tester.enterText(find.widgetWithText(TextFormField, 'Embedding 模型'), 'text-embedding-3-small');

    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(client.lastTested?.baseUrl, 'https://example.com/v1');

    expect(find.widgetWithText(FilledButton, '保存配置'), findsOneWidget);

    final controller = ProviderScope.containerOf(context).read(
      externalProviderSettingsControllerProvider,
    );
    await controller.save(
      const ExternalProviderConfig(
        id: 'openai-compatible-default',
        providerType: ExternalProviderType.openAiCompatible,
        displayName: '我的 OpenAI 兼容服务',
        baseUrl: 'https://example.com/v1',
        apiKey: 'secret-key',
        modelName: 'gpt-4.1-mini',
        embeddingModelName: 'text-embedding-3-small',
        enabled: true,
        allowSensitiveFields: false,
      ),
    );

    expect(repository.saved.single.displayName, '我的 OpenAI 兼容服务');
    expect(repository.saved.single.enabled, isTrue);
  });

  testWidgets('external provider settings page preloads saved config into the form', (tester) async {
    final repository = _MemoryExternalProviderRepository(
      configs: const [
        ExternalProviderConfig(
          id: 'openai-compatible-default',
          providerType: ExternalProviderType.openAiCompatible,
          displayName: '我的 OpenAI 兼容服务',
          baseUrl: 'https://example.com/v1',
          apiKey: 'secret-key',
          modelName: 'gpt-4.1-mini',
          embeddingModelName: 'text-embedding-3-small',
          enabled: true,
          allowSensitiveFields: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          externalProviderRepositoryProvider.overrideWithValue(repository),
          externalProviderClientProvider.overrideWithValue(_RecordingExternalProviderClient()),
        ],
        child: const MaterialApp(home: ExternalProviderSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '我的 OpenAI 兼容服务'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'https://example.com/v1'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'gpt-4.1-mini'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'text-embedding-3-small'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) {
      return widget is SwitchListTile && widget.value;
    }), findsOneWidget);
  });
}

class _MemoryExternalProviderRepository implements ExternalProviderRepository {
  _MemoryExternalProviderRepository({List<ExternalProviderConfig> configs = const <ExternalProviderConfig>[]})
      : _configs = List<ExternalProviderConfig>.from(configs);

  final List<ExternalProviderConfig> _configs;
  final List<ExternalProviderConfig> saved = <ExternalProviderConfig>[];

  @override
  Future<List<ExternalProviderConfig>> loadAll() async => List<ExternalProviderConfig>.from(_configs);

  @override
  Future<ExternalProviderConfig?> loadById(String id) async {
    for (final config in _configs.reversed) {
      if (config.id == id) {
        return config;
      }
    }
    return null;
  }

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    for (final config in _configs.reversed) {
      if (config.enabled) {
        return config;
      }
    }
    return null;
  }

  @override
  Future<void> save(ExternalProviderConfig config) async {
    _configs.removeWhere((item) => item.id == config.id);
    _configs.add(config);
    saved.add(config);
  }
}

class _RecordingExternalProviderClient implements ExternalProviderClient {
  ExternalProviderConfig? lastTested;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    return 'unused';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {
    lastTested = config;
  }
}

class _FakeChatSessionRepository implements ChatSessionRepository {
  const _FakeChatSessionRepository();

  @override
  Future<ChatSession?> getSession(String sessionId) async => null;

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async => const <ChatStoredMessage>[];

  @override
  Future<List<ChatSession>> listSessions() async => const <ChatSession>[];

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {}

  @override
  Future<void> saveSession(ChatSession session) async {}
}
