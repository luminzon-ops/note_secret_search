class ActiveModelSelection {
  const ActiveModelSelection({
    required this.activeEmbeddingModelId,
  });

  final String? activeEmbeddingModelId;

  ActiveModelSelection copyWith({
    String? activeEmbeddingModelId,
    bool clearActiveEmbeddingModelId = false,
  }) {
    return ActiveModelSelection(
      activeEmbeddingModelId: clearActiveEmbeddingModelId
          ? null
          : (activeEmbeddingModelId ?? this.activeEmbeddingModelId),
    );
  }
}
