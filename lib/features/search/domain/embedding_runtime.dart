import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

class EmbeddingModelMetadata {
  const EmbeddingModelMetadata({
    required this.tokenizer,
    required this.runtime,
  });

  final EmbeddingTokenizerSpec tokenizer;
  final EmbeddingRuntimeSpec runtime;
}

typedef EmbeddingMetadataResolver =
    Future<EmbeddingModelMetadata?> Function(String modelId);

abstract interface class EmbeddingRuntimeBridge {
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  });

  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  });

  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
    String? requestId,
  });

  Future<void> cancelRequest({required String requestId});

  Future<void> releaseModel({required String modelId});
}
