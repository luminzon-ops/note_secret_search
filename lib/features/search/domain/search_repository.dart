import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';

abstract interface class SearchRepository {
  Future<SearchScopeConfig> loadScopeConfig();

  Future<void> saveScopeConfig(SearchScopeConfig config);

  Future<List<EmbeddingChunk>> getChunksBySource(
    String sourceId,
    SearchSourceType sourceType,
    String modelId,
  );

  Future<void> upsertEmbeddingChunks(List<EmbeddingChunk> chunks);

  Future<void> removeChunksBySource(String sourceId, SearchSourceType sourceType);
}
