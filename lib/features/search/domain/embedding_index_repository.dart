import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';

abstract interface class EmbeddingIndexRepository {
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  );

  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet);

  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey);
}

class EmbeddingIndexStaleWriteException implements Exception {
  const EmbeddingIndexStaleWriteException();
}
