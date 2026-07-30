part of 'ai_chat_page_test.dart';

void _runAiChatSendPrivacyCases() {
  testWidgets('free chat tab exposes allow private context toggle', (
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
    await tester.tap(find.text('自由聊天'));
    await tester.pumpAndSettle();

    expect(find.text('允许参考私密内容'), findsOneWidget);
  });

  testWidgets(
    'free chat renders first local response after sending a message',
    (tester) async {
      final fakeLlmEngine = _RecordingLlmEngine(responseText: '这是本地首轮回答。');
      final container = await _buildContainer(
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
      expect(fakeLlmEngine.lastRequest?.prompt, contains('用户问题：\n你好，本地模型'));
      expect(fakeLlmEngine.lastRequest?.usedPrivateContext, isFalse);
    },
  );

  testWidgets(
    'free chat asks for confirmation before sending private context to external provider',
    (tester) async {
      final container = await _buildContainer(
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
          externalProviderClientRouterProvider.overrideWithValue(
            _ImmediateExternalProviderClient(),
          ),
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
      final freeSelector = find.byKey(
        const ValueKey('free-chat-backend-selector'),
      );
      await tester.tap(
        find.descendant(of: freeSelector, matching: find.text('外部')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('允许参考私密内容'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '帮我回忆 GitHub 登录信息');
      await tester.tap(find.text('发送'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('确认使用外部模型'), findsOneWidget);
      expect(find.text('包含私密上下文：是'), findsOneWidget);
    },
  );

  testWidgets(
    'private QA asks for confirmation before sending externally retrieved private context',
    (tester) async {
      final container = await _buildContainer(
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
          externalProviderClientRouterProvider.overrideWithValue(
            _ImmediateExternalProviderClient(),
          ),
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
      final privateSelector = find.byKey(
        const ValueKey('private-qa-backend-selector'),
      );
      await tester.tap(
        find.descendant(of: privateSelector, matching: find.text('外部')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '帮我总结邮箱账号');
      await tester.tap(find.text('发送'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('确认使用外部模型'), findsOneWidget);
      expect(find.text('包含私密上下文：是'), findsOneWidget);
    },
  );

  testWidgets(
    'legacy provider-id acknowledgement does not bypass fingerprint consent',
    (tester) async {
      final container = await _buildContainer(
        externalConsentStore: _MemoryExternalProviderConsentStore(
          initialValues: const <String, bool>{
            'ai.external_privacy_ack.provider-1': true,
          },
        ),
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
          externalProviderClientRouterProvider.overrideWithValue(
            _ImmediateExternalProviderClient(),
          ),
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
      final selector = find.byKey(const ValueKey('free-chat-backend-selector'));
      await tester.tap(
        find.descendant(of: selector, matching: find.text('外部')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('允许参考私密内容'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '帮我回忆 GitHub 登录信息');
      await tester.tap(find.text('发送'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('确认使用外部模型'), findsOneWidget);
    },
  );
}
