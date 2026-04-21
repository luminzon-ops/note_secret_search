import 'package:note_secret_search/features/search/domain/search_result_item.dart';

class SemanticSearchResult {
  const SemanticSearchResult({
    required this.item,
    required this.score,
    required this.hitSummary,
    required this.hitField,
  });

  final SearchResultItem item;
  final double score;
  final String hitSummary;
  final SemanticHitField hitField;
}
