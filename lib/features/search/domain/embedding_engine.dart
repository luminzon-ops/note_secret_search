import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

enum EmbeddingRuntimeStatus {
  notInstalled,
  missing,
  corrupted,
  installedUnverified,
  ready,
  degraded,
}

class EmbeddingRequest {
  const EmbeddingRequest({
    required this.model,
    required this.text,
  });

  final ModelRegistryEntry model;
  final String text;
}

class EmbeddingVector {
  const EmbeddingVector({
    required this.values,
    required this.tokenCount,
  });

  final List<double> values;
  final int tokenCount;
}

class EmbeddingEngineState {
  const EmbeddingEngineState({
    required this.ready,
    required this.reason,
    required this.status,
    this.vectorDimension,
    this.modelPath,
    this.checkedAt,
  });

  final bool ready;
  final String reason;
  final EmbeddingRuntimeStatus status;
  final int? vectorDimension;
  final String? modelPath;
  final DateTime? checkedAt;
}

abstract interface class EmbeddingEngine {
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model);

  Future<EmbeddingVector> embed(EmbeddingRequest request);
}
