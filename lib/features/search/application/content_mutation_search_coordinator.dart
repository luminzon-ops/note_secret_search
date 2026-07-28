import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/vault/domain/content_mutation_search_synchronizer.dart';

class ContentMutationSearchCoordinator
    implements ContentMutationSearchSynchronizer {
  const ContentMutationSearchCoordinator({
    required Future<ModelRegistryEntry?> Function() loadActiveEmbeddingModel,
    required Future<SearchIndexSettings> Function() loadIndexSettings,
    required Future<void> Function() indexPending,
    required void Function() invalidateSearchProjections,
  }) : _loadActiveEmbeddingModel = loadActiveEmbeddingModel,
       _loadIndexSettings = loadIndexSettings,
       _indexPending = indexPending,
       _invalidateSearchProjections = invalidateSearchProjections;

  final Future<ModelRegistryEntry?> Function() _loadActiveEmbeddingModel;
  final Future<SearchIndexSettings> Function() _loadIndexSettings;
  final Future<void> Function() _indexPending;
  final void Function() _invalidateSearchProjections;

  @override
  Future<void> synchronize() async {
    _invalidateSearchProjections();
    final activeModel = await _loadActiveEmbeddingModel();
    final indexSettings = await _loadIndexSettings();
    if (activeModel == null || !indexSettings.autoIndexEnabled) {
      return;
    }
    await _indexPending();
    _invalidateSearchProjections();
  }
}
