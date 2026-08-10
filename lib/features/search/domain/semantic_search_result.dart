export 'package:note_secret_search/features/search/domain/search_evidence.dart';

import 'package:note_secret_search/features/search/domain/search_evidence.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';

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
