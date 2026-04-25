import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';

final embeddingRuntimeBridgeProvider = Provider<EmbeddingRuntimeBridge>((ref) {
  return MethodChannelEmbeddingRuntimeBridge();
});

final embeddingEngineProvider = Provider<EmbeddingEngine>((ref) {
  return OnnxEmbeddingEngine(bridge: ref.watch(embeddingRuntimeBridgeProvider));
});
