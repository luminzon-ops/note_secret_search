import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/app/di/sensitive_state_invalidator_provider.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/ollama_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/openai_compatible_provider_client.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_editor_page.dart'
    as secret_editor;
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'sensitive_state_invalidator_test_fakes.dart';

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

void main() {
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
      final semanticService = _SensitiveSemanticSearchService(
        repository: searchRepository,
        embeddingEngine: embeddingEngine,
      );

      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
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
          semanticSearchServiceProvider.overrideWithValue(semanticService),
          searchIndexServiceProvider.overrideWithValue(
            SearchIndexService(
              repository: searchRepository,
              cryptoService: const MvpCryptoService(),
              embeddingEngine: embeddingEngine,
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

  testWidgets(
    'secret editor detail cache is purged and cannot reload while locked',
    (tester) async {
      final secretRepository = _SecretRepository();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          secretRepositoryProvider.overrideWithValue(secretRepository),
        ],
      );
      addTearDown(container.dispose);

      Future<void> pumpEditor() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: secret_editor.SecretEditorPage(
                secretId: 'secret-sensitive',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpEditor();

      expect(secretRepository.reads, 1);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).controller?.text,
        'Sensitive secret',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      container.read(sensitiveStateInvalidatorProvider).clearForLock();
      final readsAfterLock = secretRepository.reads;

      await pumpEditor();

      expect(container.read(sensitiveStateAccessAllowedProvider), isFalse);
      expect(secretRepository.reads, readsAfterLock);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).controller?.text,
        isEmpty,
      );
    },
  );
}

void _expectBlankChatState(
  ProviderContainer container,
  AiChatConversationController controller,
) {
  expect(controller.state.messages, isEmpty);
  expect(controller.state.allowPrivateContext, isFalse);
  expect(controller.state.manualItems, isEmpty);
  expect(controller.state.currentSessionId, isNull);
  expect(controller.state.errorMessage, isNull);
  expect(controller.state.suppressSessionRestore, isTrue);
  expect(container.read(currentChatSessionIdProvider), isNull);
  expect(container.read(suppressRestoredChatSessionProvider), isTrue);
}
