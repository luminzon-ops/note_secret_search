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

typedef EmbeddingIndexWriteValidator = void Function();

abstract interface class GuardedEmbeddingIndexRepository {
  Future<bool> replaceIndexSetGuarded(
    EmbeddingIndexSet indexSet, {
    required EmbeddingIndexWriteValidator validate,
  });
}

const int embeddingIndexHeaderBatchSize = 200;

abstract interface class EmbeddingIndexHeaderRepository {
  Future<Map<SearchSourceKey, EmbeddingIndexSetHeader>>
  getIndexSetHeadersBySources(
    Iterable<SearchSourceKey> sourceKeys,
    String modelId,
  );
}

class EmbeddingIndexCompatibility {
  const EmbeddingIndexCompatibility({
    required this.vaultId,
    required this.modelId,
    required this.modelRevisionHash,
    required this.fingerprintKeyId,
    required this.fingerprintVersion,
    required this.indexConfigVersion,
    required this.indexConfigEpoch,
    required this.indexConfigHash,
    required this.chunkSchemaVersion,
    required this.vectorFormatVersion,
  });

  final String vaultId;
  final String modelId;
  final String modelRevisionHash;
  final String fingerprintKeyId;
  final int fingerprintVersion;
  final int indexConfigVersion;
  final int indexConfigEpoch;
  final String indexConfigHash;
  final int chunkSchemaVersion;
  final int vectorFormatVersion;
}

abstract interface class EmbeddingIndexCorpusRepository {
  Future<List<EmbeddingIndexSet>> getCompatibleIndexSets(
    EmbeddingIndexCompatibility compatibility, {
    String? afterId,
    int limit = 100,
  });

  Future<int> purgeIncompatibleIndexSets(
    EmbeddingIndexCompatibility compatibility, {
    int batchSize = 100,
  });

  Future<int> purgeIndexSetsByIds(Iterable<String> indexSetIds);

  Future<int> purgeAllIndexSets({int batchSize = 100});
}

class EmbeddingIndexStaleWriteException implements Exception {
  const EmbeddingIndexStaleWriteException();
}
