import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';

class SemanticQualityPolicy {
  const SemanticQualityPolicy({required this.minimumSemanticScore});

  const SemanticQualityPolicy.conservativeMvp() : minimumSemanticScore = 0.82;

  final double minimumSemanticScore;

  double minimumThresholdFor(SemanticHitField field) {
    switch (field) {
      case SemanticHitField.title:
        return minimumSemanticScore;
      case SemanticHitField.username:
      case SemanticHitField.summary:
        return minimumSemanticScore + 0.02;
      case SemanticHitField.url:
      case SemanticHitField.secretNote:
        return minimumSemanticScore + 0.05;
      case SemanticHitField.noteBody:
      case SemanticHitField.tags:
        return minimumSemanticScore + 0.08;
    }
  }

  double minimumRawSimilarityFor(SearchSourceField field) {
    return switch (field) {
      SearchSourceField.secretTitle || SearchSourceField.noteTitle => 0.82,
      SearchSourceField.secretUsername || SearchSourceField.noteSummary => 0.84,
      SearchSourceField.secretWebsiteUrl ||
      SearchSourceField.secretNote => 0.87,
      SearchSourceField.secretTags ||
      SearchSourceField.noteTags ||
      SearchSourceField.noteBody => 0.90,
      SearchSourceField.secretPassword => double.infinity,
    };
  }

  double rankingWeightFor(SearchSourceField field) {
    return switch (field) {
      SearchSourceField.secretTitle || SearchSourceField.noteTitle => 1.16,
      SearchSourceField.secretUsername || SearchSourceField.noteSummary => 1.10,
      SearchSourceField.secretWebsiteUrl ||
      SearchSourceField.secretNote => 1.04,
      SearchSourceField.secretTags || SearchSourceField.noteTags => 0.96,
      SearchSourceField.noteBody => 0.92,
      SearchSourceField.secretPassword => 0,
    };
  }

  bool admitsSemanticOnly({
    required int fieldQualityTier,
    required double aggregateRankingScore,
  }) {
    return fieldQualityTier >= 2 || aggregateRankingScore >= 0.90;
  }

  String get searchPageQualityHint => '当前语义结果仅展示通过最低质量门槛的命中。';
}
