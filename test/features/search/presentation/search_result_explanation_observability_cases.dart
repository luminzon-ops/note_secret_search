part of 'search_result_explanation_test.dart';

void _runSearchResultObservabilityCases() {
  group('buildSearchObservabilitySummary', () {
    test(
      'builds keyword-only observability summary without semantic field distribution',
      () {
        final summary = buildSearchObservabilitySummary([
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
        ]);

        expect(summary.hitBreakdown, '命中结构：双命中 0 条，关键词优先 1 条，语义命中 0 条。');
        expect(summary.semanticTierBreakdown, '语义分层：重点 0 条，补充线索 0 条。');
        expect(summary.semanticFieldBreakdown, isNull);
        expect(summary.dominantSignalHint, '当前结果主要由关键词命中主导（1 条）。');
        expect(summary.dominantFieldHint, isNull);
      },
    );

    test('builds mixed observability summary with field distribution', () {
      final summary = buildSearchObservabilitySummary([
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
        SearchResultItem(
          id: 'secret-2',
          type: SearchResultType.secret,
          title: 'Card PIN',
          preview: 'pin keyword only',
          tags: const ['finance'],
          favorite: false,
          updatedAt: _searchResultTimestamp,
          matchSources: const {SearchMatchSource.keyword},
        ),
      ]);

      expect(summary.hitBreakdown, '命中结构：双命中 1 条，关键词优先 1 条，语义命中 1 条。');
      expect(summary.semanticTierBreakdown, '语义分层：重点 1 条，补充线索 1 条。');
      expect(summary.semanticFieldBreakdown, '字段分布：标题 1 条，标签 1 条。');
      expect(summary.dominantSignalHint, '当前结果主要由双命中主导（1 条）。');
      expect(summary.dominantFieldHint, '当前语义命中主要集中在标题字段（1 条）。');
    });

    test(
      'uses every semantic evidence field and exposes non-sensitive index versions',
      () {
        final summary = buildSearchObservabilitySummary([
          SearchResultItem(
            id: 'secret-1',
            type: SearchResultType.secret,
            title: 'Bank Account',
            preview: 'alice@example.com',
            tags: const ['finance'],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.semantic},
            semanticHitField: SemanticHitField.title,
            evidence: [
              SearchEvidence(
                kind: SearchEvidenceKind.semantic,
                sourceField: SearchSourceField.secretTitle,
                fieldChunkIndex: 0,
                summary: '标题：Bank Account',
                rawSimilarity: 0.94,
                weight: 1.16,
                rankingScore: 1.0904,
                threshold: 0.82,
                modelRevisionHash: 'a' * 64,
                fingerprintVersion: 1,
                indexConfigVersion: 2,
                indexConfigEpoch: 7,
                chunkSchemaVersion: 1,
                vectorFormatVersion: 1,
              ),
              SearchEvidence(
                kind: SearchEvidenceKind.semantic,
                sourceField: SearchSourceField.secretNote,
                fieldChunkIndex: 1,
                summary: '附注：backup',
                rawSimilarity: 0.91,
                weight: 1.04,
                rankingScore: 0.9464,
                threshold: 0.87,
                modelRevisionHash: 'a' * 64,
                fingerprintVersion: 1,
                indexConfigVersion: 2,
                indexConfigEpoch: 7,
                chunkSchemaVersion: 1,
                vectorFormatVersion: 1,
              ),
            ],
          ),
        ]);

        expect(summary.semanticFieldBreakdown, '字段分布：标题 1 条，附注 1 条。');
        expect(
          summary.semanticVersionBreakdown,
          '索引版本：指纹 v1，配置 v2/e7，分块 v1，向量 v1；模型修订 1 组。',
        );
      },
    );

    test('ignores semantic hit field when semantic source is absent', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'secret-1',
          type: SearchResultType.secret,
          title: 'Bank Account',
          preview: 'alice@example.com',
          tags: const ['finance'],
          favorite: false,
          updatedAt: _searchResultTimestamp,
          matchSources: const {SearchMatchSource.keyword},
          semanticHitField: SemanticHitField.title,
        ),
      ]);

      expect(summary.semanticFieldBreakdown, isNull);
      expect(summary.dominantFieldHint, isNull);
    });

    test('prefers stronger signal when dominant signal counts tie', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'a',
          type: SearchResultType.secret,
          title: 'A',
          preview: 'a',
          tags: const [],
          favorite: false,
          updatedAt: _searchResultTimestamp,
          matchSources: const {
            SearchMatchSource.keyword,
            SearchMatchSource.semantic,
          },
          semanticHitField: SemanticHitField.title,
        ),
        SearchResultItem(
          id: 'b',
          type: SearchResultType.note,
          title: 'B',
          preview: 'b',
          tags: const [],
          favorite: false,
          updatedAt: _searchResultTimestamp,
          matchSources: const {SearchMatchSource.keyword},
        ),
      ]);

      expect(summary.dominantSignalHint, '当前结果主要由双命中主导（1 条）。');
    });

    test('prefers higher-priority field when dominant field counts tie', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'a',
          type: SearchResultType.secret,
          title: 'A',
          preview: 'a',
          tags: const [],
          favorite: false,
          updatedAt: _searchResultTimestamp,
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.title,
        ),
        SearchResultItem(
          id: 'b',
          type: SearchResultType.note,
          title: 'B',
          preview: 'b',
          tags: const [],
          favorite: false,
          updatedAt: _searchResultTimestamp,
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.summary,
        ),
      ]);

      expect(summary.dominantFieldHint, '当前语义命中主要集中在标题字段（1 条）。');
    });

    test(
      'returns keyword-dominant weak-semantic reminder when keyword dominates strongly',
      () {
        final summary = buildSearchObservabilitySummary([
          SearchResultItem(
            id: 'a',
            type: SearchResultType.secret,
            title: 'A',
            preview: 'a',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.keyword},
          ),
          SearchResultItem(
            id: 'b',
            type: SearchResultType.note,
            title: 'B',
            preview: 'b',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.keyword},
          ),
          SearchResultItem(
            id: 'c',
            type: SearchResultType.note,
            title: 'C',
            preview: 'c',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.semantic},
            semanticHitField: SemanticHitField.tags,
          ),
        ]);

        expect(summary.reminderHint, '当前结果主要由关键词命中主导，语义链路参与较弱。');
      },
    );

    test(
      'buildSearchObservabilitySummary includes semantic-only filtering stats when semantic-only results are filtered',
      () {
        final summary = buildSearchObservabilitySummary(
          [
            SearchResultItem(
              id: 'dual',
              type: SearchResultType.secret,
              title: 'Dual Result',
              preview: 'dual preview',
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
              id: 'kept-semantic',
              type: SearchResultType.note,
              title: 'Kept Semantic',
              preview: 'kept preview',
              tags: const ['backup'],
              favorite: false,
              updatedAt: _searchResultTimestamp,
              matchSources: const {SearchMatchSource.semantic},
              semanticScore: 0.91,
              semanticHitField: SemanticHitField.summary,
            ),
          ],
          semanticResults: [
            SemanticSearchResult(
              item: SearchResultItem(
                id: 'dual',
                type: SearchResultType.secret,
                title: 'Dual Result',
                preview: 'dual preview',
                tags: const ['finance'],
                favorite: false,
                updatedAt: _searchResultTimestamp,
              ),
              score: 0.96,
              hitSummary: '标题：Dual Result',
              hitField: SemanticHitField.title,
            ),
            SemanticSearchResult(
              item: SearchResultItem(
                id: 'kept-semantic',
                type: SearchResultType.note,
                title: 'Kept Semantic',
                preview: 'kept preview',
                tags: const ['backup'],
                favorite: false,
                updatedAt: _searchResultTimestamp,
              ),
              score: 0.91,
              hitSummary: '摘要：Kept Semantic',
              hitField: SemanticHitField.summary,
            ),
            SemanticSearchResult(
              item: SearchResultItem(
                id: 'filtered-semantic-1',
                type: SearchResultType.note,
                title: 'Filtered 1',
                preview: 'filtered preview 1',
                tags: const ['backup'],
                favorite: false,
                updatedAt: _searchResultTimestamp,
              ),
              score: 0.72,
              hitSummary: '标签：backup',
              hitField: SemanticHitField.tags,
            ),
            SemanticSearchResult(
              item: SearchResultItem(
                id: 'filtered-semantic-2',
                type: SearchResultType.note,
                title: 'Filtered 2',
                preview: 'filtered preview 2',
                tags: const ['codes'],
                favorite: false,
                updatedAt: _searchResultTimestamp,
              ),
              score: 0.71,
              hitSummary: '正文：codes',
              hitField: SemanticHitField.noteBody,
            ),
          ],
        );

        expect(
          summary.semanticOnlyFilteringBreakdown,
          '语义过滤：语义直达候选 3 条，保留 1 条，过滤 2 条。',
        );
        expect(
          summary.semanticOnlyFilteringReason,
          '过滤原因：低质量补充语义线索 2 条，结果上限截断 0 条。',
        );
      },
    );

    test(
      'returns assist-field caution reminder when semantic participation is assist-field driven',
      () {
        final summary = buildSearchObservabilitySummary([
          SearchResultItem(
            id: 'a',
            type: SearchResultType.note,
            title: 'A',
            preview: 'a',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.semantic},
            semanticHitField: SemanticHitField.tags,
          ),
          SearchResultItem(
            id: 'b',
            type: SearchResultType.note,
            title: 'B',
            preview: 'b',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.semantic},
            semanticHitField: SemanticHitField.noteBody,
          ),
        ]);

        expect(summary.reminderHint, '当前语义参与主要来自辅助字段，建议谨慎判断结果质量。');
      },
    );

    test(
      'returns high-value field reminder when high-quality semantic hits dominate',
      () {
        final summary = buildSearchObservabilitySummary([
          SearchResultItem(
            id: 'a',
            type: SearchResultType.secret,
            title: 'A',
            preview: 'a',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {
              SearchMatchSource.keyword,
              SearchMatchSource.semantic,
            },
            semanticHitField: SemanticHitField.title,
          ),
          SearchResultItem(
            id: 'b',
            type: SearchResultType.note,
            title: 'B',
            preview: 'b',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.semantic},
            semanticHitField: SemanticHitField.summary,
          ),
        ]);

        expect(summary.reminderHint, '当前语义命中集中在高价值字段，可优先检查前排结果。');
      },
    );

    test('returns null reminder when no rule matches', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'a',
          type: SearchResultType.secret,
          title: 'A',
          preview: 'a',
          tags: const [],
          favorite: false,
          updatedAt: _searchResultTimestamp,
          matchSources: const {
            SearchMatchSource.keyword,
            SearchMatchSource.semantic,
          },
          semanticHitField: SemanticHitField.title,
        ),
      ]);

      expect(summary.reminderHint, isNull);
    });

    test(
      'uses highest-priority reminder rule when multiple rules could match',
      () {
        final summary = buildSearchObservabilitySummary([
          SearchResultItem(
            id: 'a',
            type: SearchResultType.secret,
            title: 'A',
            preview: 'a',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.keyword},
          ),
          SearchResultItem(
            id: 'b',
            type: SearchResultType.note,
            title: 'B',
            preview: 'b',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.keyword},
          ),
          SearchResultItem(
            id: 'c',
            type: SearchResultType.note,
            title: 'C',
            preview: 'c',
            tags: const [],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.semantic},
            semanticHitField: SemanticHitField.tags,
          ),
        ]);

        expect(summary.reminderHint, '当前结果主要由关键词命中主导，语义链路参与较弱。');
      },
    );
  });
}
