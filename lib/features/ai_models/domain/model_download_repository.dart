import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';

abstract interface class ModelDownloadRepository {
  Future<List<ModelDownloadTask>> listTasks();

  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId);

  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(String modelId, String sourceId);

  Future<void> saveTask(ModelDownloadTask task);
}
