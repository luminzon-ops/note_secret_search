part of 'model_download_structured_integration_test.dart';

class _ReadyEmbeddingBridge implements EmbeddingRuntimeBridge {
  int ensureCalls = 0;

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) async {
    ensureCalls += 1;
    return <String, dynamic>{
      'status': 'ready',
      'ready': true,
      'modelPath': modelPath,
    };
  }

  @override
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelRequest({required String requestId}) async {}

  @override
  Future<void> releaseModel({required String modelId}) async {}
}
