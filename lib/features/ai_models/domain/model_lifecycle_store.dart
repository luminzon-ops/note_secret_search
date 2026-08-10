import 'package:note_secret_search/core/storage/database/model_state_records.dart';
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

abstract interface class ModelInstallJournalStore {
  Future<void> saveInstallJournal(ModelInstallJournalRecord journal);

  Future<ModelInstallJournalRecord?> loadInstallJournal(String operationId);

  Future<List<ModelInstallJournalRecord>> listOpenInstallJournals();
}
