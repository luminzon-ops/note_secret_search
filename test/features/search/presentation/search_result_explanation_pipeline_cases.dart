part of 'search_result_explanation_test.dart';

void _runSearchResultPipelineCases() {
  group('buildSearchPipelineTopSummary', () {
    test('builds keyword-only top summary without semantic quality hint', () {
      final summary = buildSearchPipelineTopSummary(
        unifiedResults: [
          SearchResultItem(
            id: 'secret-1',
            type: SearchResultType.secret,
            title: 'Bank Account',
            preview: 'alice@example.com',
            tags: const ['finance'],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.keyword},
          ),
        ],
        semanticResults: const <SemanticSearchResult>[],
      );

      expect(summary.summaryText, '当前仅展示关键词检索结果，语义链路未参与此次结果排序。');
      expect(summary.keywordCount, 1);
      expect(summary.semanticResultCount, 0);
      expect(summary.showSemanticQualityHint, isFalse);
    });

    test(
      'builds mixed top summary with semantic quality hint when semantic results exist',
      () {
        final summary = buildSearchPipelineTopSummary(
          unifiedResults: [
            SearchResultItem(
              id: 'secret-1',
              type: SearchResultType.secret,
              title: 'Bank Account',
              preview: 'alice@example.com',
              tags: const ['finance'],
              favorite: false,
              updatedAt: _searchResultTimestamp,
              matchSources: const {
                SearchMatchSource.keyword,
                SearchMatchSource.semantic,
              },
              semanticScore: 0.96,
              semanticHitField: SemanticHitField.title,
            ),
            SearchResultItem(
              id: 'note-1',
              type: SearchResultType.note,
              title: 'Recovery Note',
              preview: 'backup tags',
              tags: const ['backup'],
              favorite: false,
              updatedAt: _searchResultTimestamp,
              matchSources: const {SearchMatchSource.semantic},
              semanticScore: 0.72,
              semanticHitField: SemanticHitField.tags,
            ),
          ],
          semanticResults: [
            SemanticSearchResult(
              item: SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: _searchResultTimestamp,
              ),
              score: 0.96,
              hitSummary: '标题：Bank Account',
              hitField: SemanticHitField.title,
            ),
            SemanticSearchResult(
              item: SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Recovery Note',
                preview: 'backup tags',
                tags: const ['backup'],
                favorite: false,
                updatedAt: _searchResultTimestamp,
              ),
              score: 0.72,
              hitSummary: '标签：backup',
              hitField: SemanticHitField.tags,
            ),
          ],
        );

        expect(summary.summaryText, '当前统一结果已混合关键词与语义信号，排序会优先展示双命中内容。');
        expect(summary.keywordCount, 1);
        expect(summary.semanticResultCount, 2);
        expect(summary.showSemanticQualityHint, isTrue);
        expect(
          summary.explanation.breakdown,
          '前 2 条中：双命中 1 条，关键词优先 0 条，语义命中 1 条。',
        );
        expect(
          summary.observability.hitBreakdown,
          '命中结构：双命中 1 条，关键词优先 0 条，语义命中 1 条。',
        );
      },
    );

    test(
      'does not show semantic quality hint when semantic result list is empty',
      () {
        final summary = buildSearchPipelineTopSummary(
          unifiedResults: [
            SearchResultItem(
              id: 'secret-1',
              type: SearchResultType.secret,
              title: 'Bank Account',
              preview: 'alice@example.com',
              tags: const ['finance'],
              favorite: false,
              updatedAt: _searchResultTimestamp,
              matchSources: const {SearchMatchSource.semantic},
              semanticScore: 0.96,
              semanticHitField: SemanticHitField.title,
            ),
          ],
          semanticResults: const <SemanticSearchResult>[],
        );

        expect(summary.summaryText, '当前统一结果已混合关键词与语义信号，排序会优先展示双命中内容。');
        expect(summary.showSemanticQualityHint, isFalse);
      },
    );
  });
}
