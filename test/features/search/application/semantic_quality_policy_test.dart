import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/application/semantic_quality_policy.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';

void main() {
  test('SemanticQualityPolicy conservative MVP thresholds match denoise design', () {
    const policy = SemanticQualityPolicy.conservativeMvp();
    const precision = 0.000001;

    expect(policy.minimumThresholdFor(SemanticHitField.title), closeTo(0.82, precision));
    expect(policy.minimumThresholdFor(SemanticHitField.username), closeTo(0.84, precision));
    expect(policy.minimumThresholdFor(SemanticHitField.summary), closeTo(0.84, precision));
    expect(policy.minimumThresholdFor(SemanticHitField.url), closeTo(0.87, precision));
    expect(policy.minimumThresholdFor(SemanticHitField.secretNote), closeTo(0.87, precision));
    expect(policy.minimumThresholdFor(SemanticHitField.tags), closeTo(0.90, precision));
    expect(policy.minimumThresholdFor(SemanticHitField.noteBody), closeTo(0.90, precision));
  });
}
