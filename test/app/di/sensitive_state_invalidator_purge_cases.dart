part of 'sensitive_state_invalidator_provider_test.dart';

const _embeddingModel = ModelRegistryEntry(
  id: 'embedding-sensitive',
  type: 'embedding',
  provider: 'test',
  name: 'Sensitive embedding',
  version: '1',
  sizeBytes: 1024,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'test',
  localPath: '/private/models/embedding.onnx',
  checksum: null,
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _llmModel = ModelRegistryEntry(
  id: 'llm-sensitive',
  type: 'llm',
  provider: 'test',
  name: 'Sensitive LLM',
  version: '1',
  sizeBytes: 2048,
  quantization: 'Q4',
  minRamMb: 512,
  recommendedTier: 'test',
  localPath: '/private/models/llm.gguf',
  checksum: null,
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _externalConfig = ExternalProviderConfig(
  id: 'external-sensitive',
  providerType: ExternalProviderType.ollama,
  displayName: 'Private Ollama',
  baseUrl: 'https://private-provider.example',
  apiKey: 'runtime-secret-key',
  modelName: 'private-model',
  embeddingModelName: 'private-embedding',
  enabled: true,
  allowSensitiveFields: true,
);

void registerSensitiveStateInvalidatorPurgeTests() {
  test('sensitive access gate defaults to locked', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(sensitiveStateAccessAllowedProvider), isFalse);
  });

  test(
    'clearForLock clears every sensitive cache without reloading repositories',
    () async {
      SharedPreferences.setMockInitialValues({
        'ai.active_embedding_model_id': _embeddingModel.id,
        'ai.active_llm_model_id': _llmModel.id,
      });

      final vaultRepository = _VaultRepository();
      final secretRepository = _SecretRepository();
      final noteRepository = _NoteRepository();
      final chatRepository = _ChatRepository();
      final externalRepository = _ExternalRepository();
      final registryRepository = _RegistryRepository();
      final downloadRepository = _DownloadRepository();
      final embeddingEngine = _ReadyEmbeddingEngine();
      final llmEngine = _ReadyLlmEngine();
      final searchRepository = _SearchRepository();
      final searchIndexKeyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'test-key',
            searchIndexFingerprintKey: Uint8List(32),
          ),
        );
      addTearDown(searchIndexKeyStore.clear);
      final semanticService = _SensitiveSemanticSearchService(
        repository: searchRepository,
        embeddingEngine: embeddingEngine,
      );

      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          cryptoServiceProvider.overrideWithValue(_plaintextCryptoService),
          sharedPreferencesProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
          vaultRepositoryProvider.overrideWithValue(vaultRepository),
          secretRepositoryProvider.overrideWithValue(secretRepository),
          noteRepositoryProvider.overrideWithValue(noteRepository),
          chatSessionRepositoryProvider.overrideWithValue(chatRepository),
          externalProviderRepositoryProvider.overrideWithValue(
            externalRepository,
          ),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelCatalogEntriesProvider.overrideWith((ref) async => const []),
          modelDownloadServiceProvider.overrideWithValue(
            _AlwaysPresentModelDownloadService(),
          ),
          embeddingEngineProvider.overrideWithValue(embeddingEngine),
          llmEngineProvider.overrideWithValue(llmEngine),
          searchScopeConfigProvider.overrideWith(
            (ref) async => const SearchScopeConfig.defaults(),
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
          searchIndexModelRevisionProvider.overrideWith(
            (ref, model) async => 'a' * 64,
          ),
          semanticSearchServiceProvider.overrideWithValue(semanticService),
          searchIndexServiceProvider.overrideWithValue(
            SearchIndexService(
              repository: searchRepository,
              cryptoService: _plaintextCryptoService,
              embeddingEngine: embeddingEngine,
              sessionKeyStore: searchIndexKeyStore,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(searchQueryProvider.notifier).state = 'Sensitive';
      container
          .read(searchIndexTaskStateProvider.notifier)
          .state = SearchIndexTaskState(
        running: true,
        lastCompletedAt: DateTime(2026, 7, 14),
        lastIndexedCount: 2,
        lastError: 'sensitive index error',
      );
      container
          .read(searchRefreshSessionProvider.notifier)
          .state = SearchRefreshSessionState(
        refreshing: true,
        message: 'sensitive refresh state',
        lastCompletedAt: DateTime(2026, 7, 14),
      );
      container
          .read(searchRefreshFeedbackProvider.notifier)
          .state = SearchRefreshFeedbackState(
        visible: true,
        headline: 'sensitive feedback',
        message: 'sensitive result summary',
        changed: true,
        queryAtRefresh: 'Sensitive',
        completedAt: DateTime(2026, 7, 14),
      );
      container
          .read(searchPendingReindexHandoffProvider.notifier)
          .state = const SearchPendingReindexHandoffState(
        visible: true,
        message: 'sensitive handoff',
      );

      expect(
        (await container.read(defaultVaultProvider.future))?.id,
        'vault-sensitive',
      );
      expect(await container.read(secretListProvider.future), isNotEmpty);
      expect(
        await container.read(secretDetailProvider('secret-sensitive').future),
        isNotNull,
      );
      expect(await container.read(noteListProvider.future), isNotEmpty);
      expect(
        await container.read(noteDetailProvider('note-sensitive').future),
        isNotNull,
      );
      expect(
        await container.read(keywordSearchResultsProvider.future),
        isNotEmpty,
      );
      expect(
        await container.read(semanticSearchResultsProvider.future),
        isNotEmpty,
      );
      expect(
        await container.read(unifiedSearchResultsProvider.future),
        isNotEmpty,
      );
      expect(
        (await container.read(searchIndexStatusProvider.future)).pendingItems,
        isNotEmpty,
      );

      expect(await container.read(chatSessionsProvider.future), isNotEmpty);
      expect(
        await container.read(restoredChatSessionIdProvider.future),
        isNotNull,
      );
      final freeController = container.read(
        freeChatControllerProvider.notifier,
      );
      await freeController.selectSession('chat-free');
      freeController.setAllowPrivateContext(true);
      freeController.setManualItems(const [_manualContext]);
      final privateController = container.read(
        privateQaChatControllerProvider.notifier,
      );
      await privateController.selectSession('chat-private');
      privateController.setAllowPrivateContext(true);
      privateController.setManualItems(const [_manualContext]);
      expect(
        await container.read(currentChatSessionProvider.future),
        isNotNull,
      );
      expect(
        await container.read(currentChatMessagesProvider.future),
        isNotEmpty,
      );
      expect(
        await container.read(manualContextCandidatesProvider.future),
        isNotEmpty,
      );
      expect(
        (await container.read(freeChatSemanticReadinessProvider.future)).ready,
        isTrue,
      );
      expect(
        (await container.read(privateQaSemanticReadinessProvider.future)).ready,
        isTrue,
      );

      expect(
        (await container.read(enabledExternalProviderProvider.future))?.apiKey,
        isNotEmpty,
      );
      expect(
        (await container.read(externalProviderStatusProvider.future)).available,
        isTrue,
      );
      final clientBeforeLock = container.read(externalProviderClientProvider);
      expect(clientBeforeLock, isA<OllamaProviderClient>());

      expect(
        await container.read(modelRegistryEntriesProvider.future),
        hasLength(2),
      );
      expect(
        await container.read(modelDownloadTasksProvider.future),
        isNotEmpty,
      );
      expect(
        await container.read(embeddingRuntimeStatesProvider.future),
        isNotEmpty,
      );
      expect(
        (await container.read(
          activeModelSelectionProvider.future,
        )).activeEmbeddingModelId,
        _embeddingModel.id,
      );
      expect(
        await container.read(activeEmbeddingRuntimeSelectionProvider.future),
        isNotNull,
      );
      expect(
        await container.read(activeEmbeddingModelProvider.future),
        isNotNull,
      );
      expect(
        (await container.read(semanticSearchReadinessProvider.future)).ready,
        isTrue,
      );
      expect(await container.read(llmRuntimeStatesProvider.future), isNotEmpty);
      expect(
        await container.read(activeLocalLlmModelProvider.future),
        isNotNull,
      );
      expect(
        (await container.read(localLlmReadinessProvider.future)).ready,
        isTrue,
      );

      final readsBeforeLock = [
        vaultRepository.reads,
        secretRepository.reads,
        noteRepository.reads,
        chatRepository.reads,
        externalRepository.reads,
        registryRepository.reads,
        downloadRepository.reads,
        embeddingEngine.stateReads,
        llmEngine.stateReads,
        semanticService.searchReads,
        searchRepository.chunkReads,
      ];

      container.read(sensitiveStateInvalidatorProvider).clearForLock();

      expect(container.read(sensitiveStateAccessAllowedProvider), isFalse);
      expect(container.read(searchQueryProvider), isEmpty);
      expect(container.read(searchIndexTaskStateProvider).running, isFalse);
      expect(container.read(searchIndexTaskStateProvider).lastError, isNull);
      expect(container.read(searchRefreshSessionProvider).refreshing, isFalse);
      expect(container.read(searchRefreshSessionProvider).message, isNull);
      expect(container.read(searchRefreshFeedbackProvider).visible, isFalse);
      expect(
        container.read(searchPendingReindexHandoffProvider).visible,
        isFalse,
      );
      _expectBlankChatState(container, freeController);
      _expectBlankChatState(container, privateController);

      _expectImmediateSensitiveProvidersLocked(container);

      expect(await container.read(defaultVaultProvider.future), isNull);
      expect(await container.read(secretListProvider.future), isEmpty);
      expect(
        await container.read(secretDetailProvider('secret-sensitive').future),
        isNull,
      );
      expect(await container.read(noteListProvider.future), isEmpty);
      expect(
        await container.read(noteDetailProvider('note-sensitive').future),
        isNull,
      );
      expect(
        await container.read(keywordSearchResultsProvider.future),
        isEmpty,
      );
      expect(
        await container.read(semanticSearchResultsProvider.future),
        isEmpty,
      );
      expect(
        await container.read(unifiedSearchResultsProvider.future),
        isEmpty,
      );
      expect(
        (await container.read(searchIndexStatusProvider.future)).pendingItems,
        isEmpty,
      );
      expect(await container.read(chatSessionsProvider.future), isEmpty);
      expect(
        await container.read(restoredChatSessionIdProvider.future),
        isNull,
      );
      expect(await container.read(currentChatSessionProvider.future), isNull);
      expect(await container.read(currentChatMessagesProvider.future), isEmpty);
      expect(
        await container.read(manualContextCandidatesProvider.future),
        isEmpty,
      );
      expect(
        await container.read(enabledExternalProviderProvider.future),
        isNull,
      );
      expect(
        (await container.read(externalProviderStatusProvider.future)).available,
        isFalse,
      );
      expect(
        container.read(externalProviderClientProvider),
        isA<OpenAiCompatibleProviderClient>(),
      );
      expect(
        await container.read(modelRegistryEntriesProvider.future),
        isEmpty,
      );
      expect(await container.read(modelDownloadTasksProvider.future), isEmpty);
      expect(
        await container.read(embeddingRuntimeStatesProvider.future),
        isEmpty,
      );
      expect(
        (await container.read(
          activeModelSelectionProvider.future,
        )).activeEmbeddingModelId,
        isNull,
      );
      expect(
        await container.read(activeEmbeddingRuntimeSelectionProvider.future),
        isNull,
      );
      expect(await container.read(activeEmbeddingModelProvider.future), isNull);
      final semanticReadiness = await container.read(
        semanticSearchReadinessProvider.future,
      );
      expect(semanticReadiness.ready, isFalse);
      expect(semanticReadiness.activeEmbeddingModel, isNull);
      expect(semanticReadiness.runtimeState, isNull);
      expect(await container.read(llmRuntimeStatesProvider.future), isEmpty);
      expect(await container.read(activeLocalLlmModelProvider.future), isNull);
      final llmReadiness = await container.read(
        localLlmReadinessProvider.future,
      );
      expect(llmReadiness.ready, isFalse);
      expect(llmReadiness.activeModel, isNull);
      expect(llmReadiness.runtimeState, isNull);

      expect([
        vaultRepository.reads,
        secretRepository.reads,
        noteRepository.reads,
        chatRepository.reads,
        externalRepository.reads,
        registryRepository.reads,
        downloadRepository.reads,
        embeddingEngine.stateReads,
        llmEngine.stateReads,
        semanticService.searchReads,
        searchRepository.chunkReads,
      ], readsBeforeLock);

      final preferences = await container.read(
        sharedPreferencesProvider.future,
      );
      expect(
        preferences.getString('ai.active_embedding_model_id'),
        _embeddingModel.id,
      );
      expect(preferences.getString('ai.active_llm_model_id'), _llmModel.id);
      expect((await externalRepository.loadEnabled())?.id, _externalConfig.id);
    },
  );
}
