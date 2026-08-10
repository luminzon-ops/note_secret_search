import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_runtime.dart';

final embeddingRuntimeBridgeProvider = Provider<EmbeddingRuntimeBridge>((ref) {
  throw StateError(
    'embeddingRuntimeBridgeProvider must be overridden by app composition',
  );
});

final embeddingModelMetadataResolverProvider =
    Provider<EmbeddingMetadataResolver>((ref) {
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
  throw StateError(
    'embeddingEngineProvider must be overridden by app composition',
  );
});
