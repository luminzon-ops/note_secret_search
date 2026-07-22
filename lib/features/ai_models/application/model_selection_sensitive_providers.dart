part of 'model_selection_providers.dart';

final activeModelSelectionProvider = FutureProvider<ActiveModelSelection>((
  ref,
) {
  return guardSensitiveFuture<ActiveModelSelection>(
    ref,
    lockedValue: const ActiveModelSelection(activeEmbeddingModelId: null),
    load: () async {
      final preferences = await ref.watch(sharedPreferencesProvider.future);
      final storedModelId = preferences.getString(_activeEmbeddingModelIdKey);
      if (storedModelId == null || storedModelId.isEmpty) {
        return const ActiveModelSelection(activeEmbeddingModelId: null);
      }
      Future<void> clearInvalidSelection() async {
        ref.read(searchIndexWriteFenceProvider).invalidate();
        await ref
            .read(embeddingRuntimeBridgeProvider)
            .releaseModel(modelId: storedModelId);
        await preferences.remove(_activeEmbeddingModelIdKey);
      }

      final entries = await ref.watch(modelRegistryEntriesProvider.future);
      final runtimeStates = await ref.watch(
        embeddingRuntimeStatesProvider.future,
      );
      final selectedEntry = entries
          .where(
            (entry) => entry.id == storedModelId && entry.type == 'embedding',
          )
          .firstOrNull;
      if (selectedEntry == null) {
        await clearInvalidSelection();
        return const ActiveModelSelection(activeEmbeddingModelId: null);
      }

      final runtimeState =
          runtimeStates[selectedEntry.id] ??
          _fallbackRuntimeState(selectedEntry);
      if (!selectedEntry.isInstalled || !runtimeState.ready) {
        await clearInvalidSelection();
        return const ActiveModelSelection(activeEmbeddingModelId: null);
      }

      return ActiveModelSelection(activeEmbeddingModelId: storedModelId);
    },
  );
});

final activeEmbeddingModelProvider = FutureProvider<ModelRegistryEntry?>((ref) {
  return guardSensitiveFuture<ModelRegistryEntry?>(
    ref,
    lockedValue: null,
    load: () async {
      final selectedRuntime = await ref.watch(
        activeEmbeddingRuntimeSelectionProvider.future,
      );
      return selectedRuntime?.entry.isInstalled == true
          ? selectedRuntime!.entry
          : null;
    },
  );
});

final activeEmbeddingRuntimeSelectionProvider =
    FutureProvider<SelectedEmbeddingRuntime?>((ref) {
      return guardSensitiveFuture<SelectedEmbeddingRuntime?>(
        ref,
        lockedValue: null,
        load: () async {
          final selection = await ref.watch(
            activeModelSelectionProvider.future,
          );
          final entries = await ref.watch(modelRegistryEntriesProvider.future);
          final runtimeStates = await ref.watch(
            embeddingRuntimeStatesProvider.future,
          );
          final modelId = selection.activeEmbeddingModelId;
          if (modelId == null || modelId.isEmpty) {
            return null;
          }

          for (final entry in entries) {
            if (entry.id == modelId && entry.type == 'embedding') {
              return SelectedEmbeddingRuntime(
                entry: entry,
                runtimeState:
                    runtimeStates[entry.id] ?? _fallbackRuntimeState(entry),
              );
            }
          }

          return null;
        },
      );
    });

final semanticSearchReadinessProvider = FutureProvider<SemanticSearchReadiness>(
  (ref) {
    return guardSensitiveFuture<SemanticSearchReadiness>(
      ref,
      lockedValue: const SemanticSearchReadiness(
        ready: false,
        reason: '应用已锁定。',
      ),
      load: () async {
        final selectedRuntime = await ref.watch(
          activeEmbeddingRuntimeSelectionProvider.future,
        );
        final scope = await ref.watch(searchScopeConfigProvider.future);

        if (!scope.allowLocalEmbedding) {
          return const SemanticSearchReadiness(
            ready: false,
            reason: '本地语义检索已在当前搜索范围中关闭。',
          );
        }

        if (selectedRuntime == null) {
          return const SemanticSearchReadiness(
            ready: false,
            reason: '尚未选择本地 embedding 模型。',
          );
        }

        final runtimeState = selectedRuntime.runtimeState;
        final activeEmbeddingModel = selectedRuntime.entry;
        if (!runtimeState.ready) {
          return SemanticSearchReadiness(
            ready: false,
            reason: _runtimeBlockedReason(
              activeEmbeddingModel.name,
              runtimeState,
            ),
            activeEmbeddingModel: activeEmbeddingModel,
            runtimeStatus: runtimeState.status,
            runtimeState: runtimeState,
          );
        }

        return SemanticSearchReadiness(
          ready: true,
          reason: '本地语义检索模型已就绪：${activeEmbeddingModel.name}',
          activeEmbeddingModel: activeEmbeddingModel,
          runtimeStatus: runtimeState.status,
          runtimeState: runtimeState,
        );
      },
    );
  },
);
