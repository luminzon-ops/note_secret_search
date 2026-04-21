import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';

class InMemorySearchRepository implements SearchRepository {
  SearchScopeConfig _config = const SearchScopeConfig.defaults();
  final List<EmbeddingChunk> _chunks = <EmbeddingChunk>[];

  @override
  Future<SearchScopeConfig> loadScopeConfig() async => _config;

  @override
  Future<List<EmbeddingChunk>> getChunksBySource(
    String sourceId,
    SearchSourceType sourceType,
    String modelId,
  ) async {
    return _chunks
        .where(
          (chunk) =>
              chunk.sourceId == sourceId &&
              chunk.sourceType == sourceType &&
              chunk.modelId == modelId,
        )
        .toList(growable: false);
  }

  @override
  Future<void> removeChunksBySource(String sourceId, SearchSourceType sourceType) async {
    _chunks.removeWhere(
      (chunk) => chunk.sourceId == sourceId && chunk.sourceType == sourceType,
    );
  }

  @override
  Future<void> saveScopeConfig(SearchScopeConfig config) async {
    _config = config;
  }

  @override
  Future<void> upsertEmbeddingChunks(List<EmbeddingChunk> chunks) async {
    for (final chunk in chunks) {
      _chunks.removeWhere((existing) => existing.id == chunk.id);
      _chunks.add(chunk);
    }
  }
}
