import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

abstract interface class ModelLifecycleStore {
  Future<void> commitInstallation({
    required ModelRegistryEntry registryEntry,
    required List<ModelDownloadTask> completedTasks,
  });

  Future<ModelRegistryEntry?> getDeletionManifest(String modelId);

  Future<void> purgeModelData(String modelId);
}
