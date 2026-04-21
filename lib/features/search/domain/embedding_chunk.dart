enum SearchSourceType {
  secret,
  note,
}

class EmbeddingChunk {
  const EmbeddingChunk({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.chunkIndex,
    required this.plainTextHash,
    required this.modelId,
    required this.vectorBlob,
    required this.tokenCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final SearchSourceType sourceType;
  final String sourceId;
  final int chunkIndex;
  final String plainTextHash;
  final String modelId;
  final List<int>? vectorBlob;
  final int? tokenCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}
