import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';

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

  const SearchEvidence.keyword({required this.sourceField})
    : kind = SearchEvidenceKind.keyword,
      fieldChunkIndex = null,
      summary = '',
      rawSimilarity = null,
      weight = null,
      rankingScore = null,
      threshold = null,
      modelRevisionHash = null,
      fingerprintVersion = null,
      indexConfigVersion = null,
      indexConfigEpoch = null,
      chunkSchemaVersion = null,
      vectorFormatVersion = null;

  final SearchEvidenceKind kind;
  final SearchSourceField sourceField;
  final int? fieldChunkIndex;
  final String summary;
  final double? rawSimilarity;
  final double? weight;
  final double? rankingScore;
  final double? threshold;
  final String? modelRevisionHash;
  final int? fingerprintVersion;
  final int? indexConfigVersion;
  final int? indexConfigEpoch;
  final int? chunkSchemaVersion;
  final int? vectorFormatVersion;
}
