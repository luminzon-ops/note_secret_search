import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

void main() {
  test('fusion prioritizes title hits above tag hits when semantic scores are equal', () {
    const service = SearchFusionService();

    final results = service.fuse(
      keywordResults: const <SearchResultItem>[],
      semanticResults: [
        SemanticSearchResult(
          item: SearchResultItem(
            id: 'tag-hit',
            type: SearchResultType.note,
            title: 'Tag Match',
            preview: 'finance',
            tags: const ['finance'],
            favorite: false,
            updatedAt: DateTime(2026, 1, 1),
            semanticHitField: SemanticHitField.tags,
          ),
          score: 0.9,
          hitSummary: '标签：finance',
          hitField: SemanticHitField.tags,
        ),
        SemanticSearchResult(
          item: SearchResultItem(
            id: 'title-hit',
            type: SearchResultType.note,
            title: 'Bank Account',
            preview: 'bank login',
            tags: const ['finance'],
            favorite: false,
            updatedAt: DateTime(2026, 1, 1),
            semanticHitField: SemanticHitField.title,
          ),
          score: 0.9,
          hitSummary: '标题：Bank Account',
          hitField: SemanticHitField.title,
        ),
      ],
    );

    expect(results, hasLength(2));
    expect(results.first.id, 'title-hit');
    expect(results.last.id, 'tag-hit');
  });
}
