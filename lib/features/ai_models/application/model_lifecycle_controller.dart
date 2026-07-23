import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/application/model_session_releaser.dart';

typedef ReleaseEmbeddingModel = Future<void> Function(String modelId);
typedef InvalidateEmbeddingWrites = void Function();

class ModelLifecycleController {
  ModelLifecycleController({
    required ModelLifecycleStore lifecycleStore,
    required ModelArtifactStore artifactStore,
    ModelSessionReleaser? sessionReleaser,
    InvalidateEmbeddingWrites? invalidateEmbeddingWrites,
    ReleaseEmbeddingModel? releaseEmbeddingModel,
  }) : _lifecycleStore = lifecycleStore,
       _artifactStore = artifactStore,
       _sessionReleaser = sessionReleaser,
       _invalidateEmbeddingWrites = invalidateEmbeddingWrites,
       _releaseEmbeddingModel = releaseEmbeddingModel;

  final ModelLifecycleStore _lifecycleStore;
  final ModelArtifactStore _artifactStore;
  final ModelSessionReleaser? _sessionReleaser;
  final InvalidateEmbeddingWrites? _invalidateEmbeddingWrites;
  final ReleaseEmbeddingModel? _releaseEmbeddingModel;

  Future<void> deleteInstalledModel(String modelId) async {
    if (modelId.trim().isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'Model id is required.');
    }
    final manifest = await _lifecycleStore.getDeletionManifest(modelId);
    await prepareForMutation(modelId, modelType: manifest?.type);
    await _artifactStore.deleteModelArtifacts(
      modelId: modelId,
      primaryPath: manifest?.localPath,
      artifacts: manifest?.artifacts ?? const [],
    );
    await _lifecycleStore.purgeModelData(modelId);
  }

  Future<void> prepareForMutation(
    String modelId, {
    required String? modelType,
  }) async {
    final releaser = _sessionReleaser;
    if (releaser != null) {
      await releaser.releaseForMutation(modelId, modelType: modelType);
      return;
    }
    if (modelType == 'embedding') {
      _invalidateEmbeddingWrites?.call();
      await _releaseEmbeddingModel?.call(modelId);
    }
  }
}
