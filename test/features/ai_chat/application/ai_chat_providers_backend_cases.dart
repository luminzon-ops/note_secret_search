part of 'ai_chat_providers_test.dart';

void _runAiChatBackendCases() {
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
}
