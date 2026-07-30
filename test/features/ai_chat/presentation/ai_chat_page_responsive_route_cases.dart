part of 'ai_chat_page_test.dart';

void _runAiChatResponsiveRouteCases() {
  for (final width in <double>[393, 839]) {
    testWidgets(
      'AI chat uses drawer-based recent sessions at ${width.toInt()} logical pixels',
      (tester) async {
        final container = await _buildContainer(
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

        await _pumpChatRouteAtSize(tester, container, size: Size(width, 800));

        expect(find.text('最近会话'), findsNothing);
        final openRecentSessions = find.byTooltip('打开最近会话');
        expect(openRecentSessions, findsOneWidget);

        await revealAndTap(tester, openRecentSessions);
        await pumpUntilFound(tester, find.text('最近会话'));

        expect(find.text('最近会话'), findsOneWidget);
        expect(find.widgetWithText(ListTile, '邮箱问答'), findsOneWidget);
      },
    );
  }

  for (final width in <double>[840, 1280]) {
    testWidgets(
      'AI chat uses persistent recent sessions at ${width.toInt()} logical pixels',
      (tester) async {
        final container = await _buildContainer(
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

        await _pumpChatRouteAtSize(tester, container, size: Size(width, 800));

        expect(find.text('最近会话'), findsOneWidget);
        expect(find.byTooltip('打开最近会话'), findsNothing);
        expect(find.widgetWithText(ListTile, '邮箱问答'), findsOneWidget);
      },
    );
  }

  testWidgets('App shell shows 问答 navigation destination on AI chat route', (
    tester,
  ) async {
    final container = await _buildContainer();

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
    final container = await _buildContainer();

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

    expect(find.text('私密内容问答'), findsOneWidget);
    expect(find.text('自由聊天'), findsOneWidget);
  });

  testWidgets(
    'AI chat page shows jump-to-model-management CTA when llm is unavailable',
    (tester) async {
      final container = await _buildContainer(
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
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('前往模型管理'), findsOneWidget);
    },
  );

  testWidgets(
    'AI chat page shows external provider banner when local llm is unavailable but external provider is ready',
    (tester) async {
      final container = await _buildContainer(
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
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('外部模型已可用：OpenAI 兼容服务'), findsOneWidget);
      expect(find.text('前往模型管理'), findsNothing);
    },
  );
}
