import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';

abstract interface class ModelArtifactStore {
  Future<void> deleteModelArtifacts({
    required String modelId,
    required String? primaryPath,
    required List<ModelArtifactPath> artifacts,
  });
}
