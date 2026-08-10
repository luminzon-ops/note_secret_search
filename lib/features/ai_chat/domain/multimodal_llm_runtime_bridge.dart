abstract interface class MultimodalLlmRuntimeBridge {
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    required String mmprojPath,
  });

  Future<Map<String, dynamic>> generateMultimodalText({
    required String modelId,
    required String modelPath,
    required String mmprojPath,
    required String imagePath,
    required String prompt,
    required int maxOutputTokens,
    required int contextLength,
    required bool reasoningEnabled,
  });
}
