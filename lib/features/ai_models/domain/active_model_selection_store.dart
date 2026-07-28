abstract interface class ActiveModelSelectionStore {
  Future<String?> loadActiveEmbeddingModelId();

  Future<void> saveActiveEmbeddingModelId(String? modelId);
}
