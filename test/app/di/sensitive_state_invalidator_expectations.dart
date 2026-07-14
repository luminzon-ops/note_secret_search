part of 'sensitive_state_invalidator_provider_test.dart';

void _expectImmediateSensitiveProvidersLocked(ProviderContainer container) {
  _expectImmediateLockedValue(container.read(defaultVaultProvider), isNull);
  _expectImmediateLockedValue(container.read(secretListProvider), isEmpty);
  _expectImmediateLockedValue(
    container.read(secretDetailProvider('secret-sensitive')),
    isNull,
  );
  _expectImmediateLockedValue(container.read(noteListProvider), isEmpty);
  _expectImmediateLockedValue(
    container.read(noteDetailProvider('note-sensitive')),
    isNull,
  );
  _expectImmediateLockedValue(
    container.read(keywordSearchResultsProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(semanticSearchResultsProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(unifiedSearchResultsProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(searchIndexStatusProvider),
    isA<SearchIndexStatus>()
        .having((status) => status.engineReady, 'engineReady', isFalse)
        .having((status) => status.pendingItems, 'pendingItems', isEmpty),
  );
  _expectImmediateLockedValue(container.read(chatSessionsProvider), isEmpty);
  _expectImmediateLockedValue(
    container.read(restoredChatSessionIdProvider),
    isNull,
  );
  _expectImmediateLockedValue(
    container.read(currentChatSessionProvider),
    isNull,
  );
  _expectImmediateLockedValue(
    container.read(currentChatMessagesProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(manualContextCandidatesProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(freeChatSemanticReadinessProvider),
    isA<SemanticSearchReadiness>()
        .having((readiness) => readiness.ready, 'ready', isFalse)
        .having(
          (readiness) => readiness.activeEmbeddingModel,
          'activeEmbeddingModel',
          isNull,
        )
        .having((readiness) => readiness.runtimeState, 'runtimeState', isNull),
  );
  _expectImmediateLockedValue(
    container.read(privateQaSemanticReadinessProvider),
    isA<SemanticSearchReadiness>()
        .having((readiness) => readiness.ready, 'ready', isFalse)
        .having(
          (readiness) => readiness.activeEmbeddingModel,
          'activeEmbeddingModel',
          isNull,
        )
        .having((readiness) => readiness.runtimeState, 'runtimeState', isNull),
  );
  _expectImmediateLockedValue(
    container.read(enabledExternalProviderProvider),
    isNull,
  );
  _expectImmediateLockedValue(
    container.read(externalProviderStatusProvider),
    isA<ExternalProviderStatus>()
        .having((status) => status.available, 'available', isFalse)
        .having((status) => status.config, 'config', isNull),
  );
  expect(
    container.read(externalProviderClientProvider),
    isA<OpenAiCompatibleProviderClient>(),
  );
  _expectImmediateLockedValue(
    container.read(modelRegistryEntriesProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(modelDownloadTasksProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(embeddingRuntimeStatesProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(activeModelSelectionProvider),
    isA<ActiveModelSelection>().having(
      (selection) => selection.activeEmbeddingModelId,
      'activeEmbeddingModelId',
      isNull,
    ),
  );
  _expectImmediateLockedValue(
    container.read(activeEmbeddingRuntimeSelectionProvider),
    isNull,
  );
  _expectImmediateLockedValue(
    container.read(activeEmbeddingModelProvider),
    isNull,
  );
  _expectImmediateLockedValue(
    container.read(semanticSearchReadinessProvider),
    isA<SemanticSearchReadiness>()
        .having((readiness) => readiness.ready, 'ready', isFalse)
        .having(
          (readiness) => readiness.activeEmbeddingModel,
          'activeEmbeddingModel',
          isNull,
        )
        .having((readiness) => readiness.runtimeState, 'runtimeState', isNull),
  );
  _expectImmediateLockedValue(
    container.read(llmRuntimeStatesProvider),
    isEmpty,
  );
  _expectImmediateLockedValue(
    container.read(activeLocalLlmModelProvider),
    isNull,
  );
  _expectImmediateLockedValue(
    container.read(localLlmReadinessProvider),
    isA<LocalLlmReadiness>()
        .having((readiness) => readiness.ready, 'ready', isFalse)
        .having((readiness) => readiness.activeModel, 'activeModel', isNull)
        .having((readiness) => readiness.runtimeState, 'runtimeState', isNull),
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

void _expectImmediateLockedValue<T>(AsyncValue<T> asyncValue, Matcher matcher) {
  expect(asyncValue.hasValue, isTrue);
  expect(asyncValue.valueOrNull, matcher);
}
