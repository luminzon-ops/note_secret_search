part of 'ai_chat_providers_test.dart';

void _runAiChatContextCases() {
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
}
