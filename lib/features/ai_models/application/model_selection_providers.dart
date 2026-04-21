import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/domain/active_model_selection.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

final activeModelSelectionProvider = FutureProvider<ActiveModelSelection>((ref) async {
  final preferences = await ref.watch(sharedPreferencesProvider.future);
  return ActiveModelSelection(
    activeEmbeddingModelId: preferences.getString(_activeEmbeddingModelIdKey),
  );
});

final activeEmbeddingModelProvider = FutureProvider<ModelRegistryEntry?>((ref) async {
  final selection = await ref.watch(activeModelSelectionProvider.future);
  final entries = await ref.watch(modelRegistryEntriesProvider.future);
  final modelId = selection.activeEmbeddingModelId;
  if (modelId == null || modelId.isEmpty) {
    return null;
  }

  for (final entry in entries) {
    if (entry.id == modelId && entry.isInstalled && entry.type == 'embedding') {
      return entry;
    }
  }

  return null;
});

final semanticSearchReadinessProvider = FutureProvider<SemanticSearchReadiness>((ref) async {
  final activeEmbeddingModel = await ref.watch(activeEmbeddingModelProvider.future);
  final scope = await ref.watch(searchScopeConfigProvider.future);

  if (!scope.allowLocalEmbedding) {
    return const SemanticSearchReadiness(
      ready: false,
      reason: '本地语义检索已在当前搜索范围中关闭。',
    );
  }

  if (activeEmbeddingModel == null) {
    return const SemanticSearchReadiness(
      ready: false,
      reason: '尚未选择可用的本地 embedding 模型。',
    );
  }

  return SemanticSearchReadiness(
    ready: true,
    reason: '本地语义检索模型已就绪：${activeEmbeddingModel.name}',
    activeEmbeddingModel: activeEmbeddingModel,
  );
});

final activeModelSelectionControllerProvider = Provider<ActiveModelSelectionController>((ref) {
  return ActiveModelSelectionController(ref: ref);
});

class ActiveModelSelectionController {
  ActiveModelSelectionController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> setActiveEmbeddingModel(String? modelId) async {
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    if (modelId == null || modelId.isEmpty) {
      await preferences.remove(_activeEmbeddingModelIdKey);
    } else {
      await preferences.setString(_activeEmbeddingModelIdKey, modelId);
    }

    _ref.invalidate(activeModelSelectionProvider);
    _ref.invalidate(activeEmbeddingModelProvider);
    _ref.invalidate(semanticSearchReadinessProvider);
  }
}

class SemanticSearchReadiness {
  const SemanticSearchReadiness({
    required this.ready,
    required this.reason,
    this.activeEmbeddingModel,
  });

  final bool ready;
  final String reason;
  final ModelRegistryEntry? activeEmbeddingModel;
}

const _activeEmbeddingModelIdKey = 'ai.active_embedding_model_id';
