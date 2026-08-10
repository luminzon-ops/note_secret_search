abstract interface class LlmRuntimeBridge {
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  });

  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  });

  Future<Map<String, dynamic>> generateText({
    required String modelId,
    required String modelPath,
    required String prompt,
    required bool usedPrivateContext,
    required int maxOutputTokens,
    required int maxPromptChars,
    required int contextLength,
    required bool conservativeMode,
    required double temperature,
    required int topK,
    required double topP,
    required int seed,
    required List<String> stopSequences,
    required bool emitPartialCompletion,
  });

  Future<void> releaseModel({required String modelId});
}

abstract interface class RequestIdentifiedLlmRuntimeBridge {
  Future<Map<String, dynamic>> ensureIdentifiedModelReady({
    required String modelId,
    required String modelPath,
    required String? verifiedChecksum,
  });

  Future<Map<String, dynamic>> generateIdentifiedText({
    required String requestId,
    required String modelId,
    required String modelPath,
    required String? verifiedChecksum,
    required String prompt,
    required bool usedPrivateContext,
    required int maxOutputTokens,
    required int maxPromptChars,
    required int contextLength,
    required bool conservativeMode,
    required double temperature,
    required int topK,
    required double topP,
    required int seed,
    required List<String> stopSequences,
    required bool emitPartialCompletion,
  });

  Future<void> cancelGeneration({required String requestId});
}
