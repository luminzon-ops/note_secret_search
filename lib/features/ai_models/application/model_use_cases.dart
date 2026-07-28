import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/application/local_llm_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_sensitive_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

typedef StartModelDownload =
    Future<void> Function({
      required ModelCatalogEntry entry,
      required ModelSourceEntry source,
    });
typedef PauseModelDownload =
    Future<void> Function(String modelId, {required String sourceId});
typedef ModelIdCommand = Future<void> Function(String modelId);
typedef MarkModelDownloadFailed =
    Future<void> Function(
      String modelId, {
      required String sourceId,
      required String message,
    });
typedef SetActiveModel = Future<void> Function(String? modelId);

final modelMaintenanceUseCaseProvider = Provider<ModelMaintenanceUseCase>((
  ref,
) {
  final controller = ref.watch(modelDownloadControllerProvider);
  return ModelMaintenanceUseCase(
    startDownload: controller.startDownload,
    pause: controller.pause,
    delete: controller.deleteInstalledModel,
    revalidate: controller.revalidateInstalledModel,
    repair: controller.repairInstalledModel,
    markFailed: controller.markFailedForSource,
  );
});

final modelActivationUseCaseProvider = Provider<ModelActivationUseCase>((ref) {
  return ModelActivationUseCase(
    setEmbedding: ref
        .watch(activeModelSelectionControllerProvider)
        .setActiveEmbeddingModel,
    setLocalLlm: ref
        .watch(activeLocalLlmSelectionControllerProvider)
        .setActiveLocalLlmModel,
  );
});

class ModelMaintenanceUseCase {
  const ModelMaintenanceUseCase({
    required StartModelDownload startDownload,
    required PauseModelDownload pause,
    required ModelIdCommand delete,
    required ModelIdCommand revalidate,
    required ModelIdCommand repair,
    required MarkModelDownloadFailed markFailed,
  }) : _startDownload = startDownload,
       _pause = pause,
       _delete = delete,
       _revalidate = revalidate,
       _repair = repair,
       _markFailed = markFailed;

  final StartModelDownload _startDownload;
  final PauseModelDownload _pause;
  final ModelIdCommand _delete;
  final ModelIdCommand _revalidate;
  final ModelIdCommand _repair;
  final MarkModelDownloadFailed _markFailed;

  Future<void> start({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
  }) {
    return _startDownload(entry: entry, source: source);
  }

  Future<void> pause(String modelId, {required String sourceId}) {
    return _pause(modelId, sourceId: sourceId);
  }

  Future<void> delete(String modelId) => _delete(modelId);

  Future<void> revalidate(String modelId) => _revalidate(modelId);

  Future<void> repair(String modelId) => _repair(modelId);

  Future<void> markFailed(
    String modelId, {
    required String sourceId,
    required String message,
  }) {
    return _markFailed(modelId, sourceId: sourceId, message: message);
  }
}

class ModelActivationUseCase {
  const ModelActivationUseCase({
    required SetActiveModel setEmbedding,
    required SetActiveModel setLocalLlm,
  }) : _setEmbedding = setEmbedding,
       _setLocalLlm = setLocalLlm;

  final SetActiveModel _setEmbedding;
  final SetActiveModel _setLocalLlm;

  Future<void> setEmbedding(String? modelId) => _setEmbedding(modelId);

  Future<void> setLocalLlm(String? modelId) => _setLocalLlm(modelId);
}
