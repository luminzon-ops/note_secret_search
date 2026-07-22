import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';

typedef ReleaseEmbeddingModel = Future<void> Function(String modelId);
typedef InvalidateEmbeddingWrites = void Function();

class ModelLifecycleController {
  const ModelLifecycleController({
    required ModelLifecycleStore lifecycleStore,
    required ModelArtifactStore artifactStore,
    InvalidateEmbeddingWrites? invalidateEmbeddingWrites,
    ReleaseEmbeddingModel? releaseEmbeddingModel,
  }) : _lifecycleStore = lifecycleStore,
       _artifactStore = artifactStore,
       _invalidateEmbeddingWrites = invalidateEmbeddingWrites,
       _releaseEmbeddingModel = releaseEmbeddingModel;

  final ModelLifecycleStore _lifecycleStore;
  final ModelArtifactStore _artifactStore;
  final InvalidateEmbeddingWrites? _invalidateEmbeddingWrites;
  final ReleaseEmbeddingModel? _releaseEmbeddingModel;

  Future<void> deleteInstalledModel(String modelId) async {
    if (modelId.trim().isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'Model id is required.');
    }
    final manifest = await _lifecycleStore.getDeletionManifest(modelId);
    if (manifest?.type == 'embedding') {
      _invalidateEmbeddingWrites?.call();
      await _releaseEmbeddingModel?.call(modelId);
    }
    await _artifactStore.deleteModelArtifacts(
      modelId: modelId,
      primaryPath: manifest?.localPath,
      artifacts: manifest?.artifacts ?? const [],
    );
    await _lifecycleStore.purgeModelData(modelId);
  }
}
