abstract interface class LocalLlmSelectionStore {
  Future<String?> loadActiveModelId();

  Future<void> saveActiveModelId(String? modelId);
}
