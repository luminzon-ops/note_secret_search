import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

enum ModelRuntimeStatus {
  notInstalled,
  missing,
  corrupted,
  installedUnverified,
  ready,
  degraded,
}

class ModelRuntimeState {
  const ModelRuntimeState({
    required this.ready,
    required this.reason,
    required this.status,
    this.modelPath,
    this.checkedAt,
  });

  final bool ready;
  final String reason;
  final ModelRuntimeStatus status;
  final String? modelPath;
  final DateTime? checkedAt;

  bool get acceptsInstallation =>
      status == ModelRuntimeStatus.ready ||
      status == ModelRuntimeStatus.installedUnverified;
}

abstract interface class ModelRuntimeCoordinator {
  Future<ModelRuntimeState> inspectInstalledModel(ModelRegistryEntry entry);

  Future<ModelRuntimeState> validateCandidate({
    required ModelCatalogEntry entry,
    required String modelPath,
    required String verifiedChecksum,
    String? multimodalProjectorPath,
  });

  Future<void> releaseForMutation(String modelId, {required String? modelType});
}
