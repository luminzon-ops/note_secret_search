import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';

class ModelLifecycleController {
  const ModelLifecycleController({
    required ModelLifecycleStore lifecycleStore,
    required ModelArtifactStore artifactStore,
  }) : _lifecycleStore = lifecycleStore,
       _artifactStore = artifactStore;

  final ModelLifecycleStore _lifecycleStore;
  final ModelArtifactStore _artifactStore;

  Future<void> deleteInstalledModel(String modelId) async {
    if (modelId.trim().isEmpty) {
      throw ArgumentError.value(modelId, 'modelId', 'Model id is required.');
    }
    final manifest = await _lifecycleStore.getDeletionManifest(modelId);
    await _artifactStore.deleteModelArtifacts(
      modelId: modelId,
      primaryPath: manifest?.localPath,
      artifacts: manifest?.artifacts ?? const [],
    );
    await _lifecycleStore.purgeModelData(modelId);
  }
}
