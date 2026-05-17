import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';

final embeddingRuntimeBridgeProvider = Provider<EmbeddingRuntimeBridge>((ref) {
  return MethodChannelEmbeddingRuntimeBridge();
});

final embeddingModelMetadataResolverProvider = Provider<EmbeddingMetadataResolver>((ref) {
  return (modelId) async {
    final entries = await ref.read(modelCatalogEntriesProvider.future);
    for (final entry in entries) {
      if (entry.id != modelId) {
        continue;
      }

      final tokenizer = entry.tokenizer;
      final runtime = entry.runtime;
      if (tokenizer == null || runtime == null) {
        return null;
      }

      return EmbeddingModelMetadata(tokenizer: tokenizer, runtime: runtime);
    }

    return null;
  };
});

final embeddingEngineProvider = Provider<EmbeddingEngine>((ref) {
  return OnnxEmbeddingEngine(
    bridge: ref.watch(embeddingRuntimeBridgeProvider),
    resolveMetadata: ref.watch(embeddingModelMetadataResolverProvider),
  );
});
