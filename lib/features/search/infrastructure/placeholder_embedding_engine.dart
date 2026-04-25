import 'dart:convert';

import 'package:note_secret_search/features/search/domain/embedding_engine.dart';

class PlaceholderEmbeddingEngine implements EmbeddingEngine {
  const PlaceholderEmbeddingEngine();

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    final normalized = request.text.trim();
    if (normalized.isEmpty) {
      return const EmbeddingVector(values: <double>[0, 0, 0, 0], tokenCount: 0);
    }

    final bytes = utf8.encode(normalized);
    final buckets = List<double>.filled(4, 0);
    for (var index = 0; index < bytes.length; index++) {
      buckets[index % buckets.length] += bytes[index].toDouble();
    }

    return EmbeddingVector(
      values: buckets,
      tokenCount: normalized.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length,
    );
  }

  @override
  Future<EmbeddingEngineState> getState(model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: '当前使用占位 embedding 引擎，仅用于索引链路打通，不代表真实语义质量。',
      status: EmbeddingRuntimeStatus.installedUnverified,
    );
  }
}
