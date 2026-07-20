import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';

enum SearchEvidenceKind { keyword, semantic }

class SearchEvidence {
  const SearchEvidence({
    required this.kind,
    required this.sourceField,
    required this.fieldChunkIndex,
    required this.summary,
    required this.rawSimilarity,
    required this.weight,
    required this.rankingScore,
    required this.threshold,
    required this.modelRevisionHash,
    required this.fingerprintVersion,
    required this.indexConfigVersion,
    required this.indexConfigEpoch,
    required this.chunkSchemaVersion,
    required this.vectorFormatVersion,
  });

  final SearchEvidenceKind kind;
  final SearchSourceField sourceField;
  final int fieldChunkIndex;
  final String summary;
  final double rawSimilarity;
  final double weight;
  final double rankingScore;
  final double threshold;
  final String modelRevisionHash;
  final int fingerprintVersion;
  final int indexConfigVersion;
  final int indexConfigEpoch;
  final int chunkSchemaVersion;
  final int vectorFormatVersion;
}

class SemanticSearchResult {
  const SemanticSearchResult({
    required this.item,
    required this.score,
    required this.hitSummary,
    required this.hitField,
    this.primaryRawSimilarity,
    this.evidence = const <SearchEvidence>[],
    this.queryAffinity = 0,
    this.fieldQualityTier = 0,
  });

  final SearchResultItem item;
  final double score;
  final String hitSummary;
  final SemanticHitField hitField;
  final double? primaryRawSimilarity;
  final List<SearchEvidence> evidence;
  final int queryAffinity;
  final int fieldQualityTier;
}
