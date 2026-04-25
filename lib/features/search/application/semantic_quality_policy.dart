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

  String get searchPageQualityHint => '当前语义结果仅展示通过最低质量门槛的命中。';
}
