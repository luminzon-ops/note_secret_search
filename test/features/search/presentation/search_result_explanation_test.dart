import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/presentation/search_result_explanation.dart';

void main() {
  group('buildSearchResultCardExplanation', () {
    test('returns dual high-quality explanation for dual-hit high-quality semantic result', () {
      final explanation = buildSearchResultCardExplanation(
        SearchResultItem(
          id: 'secret-1',
          type: SearchResultType.secret,
          title: 'Bank Account',
          preview: 'alice@example.com',
          tags: const ['finance'],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.title,
        ),
      );

      expect(explanation, '这条结果同时命中关键词与重点语义字段，可优先查看。');
    });

    test('returns dual assist explanation for dual-hit assist semantic result', () {
      final explanation = buildSearchResultCardExplanation(
        SearchResultItem(
          id: 'note-1',
          type: SearchResultType.note,
          title: 'Recovery Note',
          preview: 'backup tags',
          tags: const ['backup'],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.tags,
        ),
      );

      expect(explanation, '这条结果同时命中关键词，语义部分主要提供补充线索，建议结合预览确认。');
    });

    test('returns keyword-primary explanation for keyword-only result', () {
      final explanation = buildSearchResultCardExplanation(
        SearchResultItem(
          id: 'secret-2',
          type: SearchResultType.secret,
          title: 'Card PIN',
          preview: 'pin keyword only',
          tags: const ['finance'],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword},
        ),
      );

      expect(explanation, '这条结果主要由关键词命中进入结果。');
    });

    test('returns semantic high-quality explanation for semantic-only high-quality result', () {
      final explanation = buildSearchResultCardExplanation(
        SearchResultItem(
          id: 'secret-3',
          type: SearchResultType.secret,
          title: 'Vault Account',
          preview: 'vault@example.com',
          tags: const ['vault'],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.summary,
        ),
      );

      expect(explanation, '这条结果主要由重点语义命中支持，适合优先检查。');
    });

    test('returns semantic assist explanation for semantic-only assist result', () {
      final explanation = buildSearchResultCardExplanation(
        SearchResultItem(
          id: 'note-2',
          type: SearchResultType.note,
          title: 'Codes Note',
          preview: 'body hit',
          tags: const ['codes'],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.noteBody,
        ),
      );

      expect(explanation, '这条结果主要由补充语义线索召回，建议继续确认。');
    });
  });

  group('buildSearchObservabilitySummary', () {
    test('builds keyword-only observability summary without semantic field distribution', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'secret-1',
          type: SearchResultType.secret,
          title: 'Bank Account',
          preview: 'alice@example.com',
          tags: const ['finance'],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword},
        ),
      ]);

      expect(summary.hitBreakdown, '命中结构：双命中 0 条，关键词优先 1 条，语义命中 0 条。');
      expect(summary.semanticTierBreakdown, '语义分层：重点 0 条，补充线索 0 条。');
      expect(summary.semanticFieldBreakdown, isNull);
      expect(summary.dominantSignalHint, '当前结果主要由关键词命中主导（1 条）。');
      expect(summary.dominantFieldHint, isNull);
    });

    test('builds mixed observability summary with field distribution', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'secret-1',
          type: SearchResultType.secret,
          title: 'Bank Account',
          preview: 'alice@example.com',
          tags: const ['finance'],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
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
          updatedAt: DateTime(2026, 1, 2),
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
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword},
        ),
      ]);

      expect(summary.hitBreakdown, '命中结构：双命中 1 条，关键词优先 1 条，语义命中 1 条。');
      expect(summary.semanticTierBreakdown, '语义分层：重点 1 条，补充线索 1 条。');
      expect(summary.semanticFieldBreakdown, '字段分布：标题 1 条，标签 1 条。');
      expect(summary.dominantSignalHint, '当前结果主要由双命中主导（1 条）。');
      expect(summary.dominantFieldHint, '当前语义命中主要集中在标题字段（1 条）。');
    });

    test('ignores semantic hit field when semantic source is absent', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'secret-1',
          type: SearchResultType.secret,
          title: 'Bank Account',
          preview: 'alice@example.com',
          tags: const ['finance'],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
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
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.title,
        ),
        SearchResultItem(
          id: 'b',
          type: SearchResultType.note,
          title: 'B',
          preview: 'b',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
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
          updatedAt: DateTime(2026, 1, 2),
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
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.summary,
        ),
      ]);

      expect(summary.dominantFieldHint, '当前语义命中主要集中在标题字段（1 条）。');
    });

    test('returns keyword-dominant weak-semantic reminder when keyword dominates strongly', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'a',
          type: SearchResultType.secret,
          title: 'A',
          preview: 'a',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword},
        ),
        SearchResultItem(
          id: 'b',
          type: SearchResultType.note,
          title: 'B',
          preview: 'b',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword},
        ),
        SearchResultItem(
          id: 'c',
          type: SearchResultType.note,
          title: 'C',
          preview: 'c',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.tags,
        ),
      ]);

      expect(summary.reminderHint, '当前结果主要由关键词命中主导，语义链路参与较弱。');
    });

    test('buildSearchObservabilitySummary includes semantic-only filtering stats when semantic-only results are filtered', () {
      final summary = buildSearchObservabilitySummary(
        [
          SearchResultItem(
            id: 'dual',
            type: SearchResultType.secret,
            title: 'Dual Result',
            preview: 'dual preview',
            tags: const ['finance'],
            favorite: false,
            updatedAt: DateTime(2026, 1, 2),
            matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
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
            updatedAt: DateTime(2026, 1, 2),
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
              updatedAt: DateTime(2026, 1, 2),
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
              updatedAt: DateTime(2026, 1, 2),
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
              updatedAt: DateTime(2026, 1, 2),
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
              updatedAt: DateTime(2026, 1, 2),
            ),
            score: 0.71,
            hitSummary: '正文：codes',
            hitField: SemanticHitField.noteBody,
          ),
        ],
      );

      expect(summary.semanticOnlyFilteringBreakdown, '语义过滤：语义直达候选 2 条，保留 1 条，过滤 1 条。');
      expect(summary.semanticOnlyFilteringReason, '过滤原因：被过滤结果多数只提供补充语义线索，且未达到高分保留条件。');
    });

    test('returns assist-field caution reminder when semantic participation is assist-field driven', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'a',
          type: SearchResultType.note,
          title: 'A',
          preview: 'a',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
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
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.noteBody,
        ),
      ]);

      expect(summary.reminderHint, '当前语义参与主要来自辅助字段，建议谨慎判断结果质量。');
    });

    test('returns high-value field reminder when high-quality semantic hits dominate', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'a',
          type: SearchResultType.secret,
          title: 'A',
          preview: 'a',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.title,
        ),
        SearchResultItem(
          id: 'b',
          type: SearchResultType.note,
          title: 'B',
          preview: 'b',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.summary,
        ),
      ]);

      expect(summary.reminderHint, '当前语义命中集中在高价值字段，可优先检查前排结果。');
    });

    test('returns null reminder when no rule matches', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'a',
          type: SearchResultType.secret,
          title: 'A',
          preview: 'a',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.title,
        ),
      ]);

      expect(summary.reminderHint, isNull);
    });

    test('uses highest-priority reminder rule when multiple rules could match', () {
      final summary = buildSearchObservabilitySummary([
        SearchResultItem(
          id: 'a',
          type: SearchResultType.secret,
          title: 'A',
          preview: 'a',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword},
        ),
        SearchResultItem(
          id: 'b',
          type: SearchResultType.note,
          title: 'B',
          preview: 'b',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.keyword},
        ),
        SearchResultItem(
          id: 'c',
          type: SearchResultType.note,
          title: 'C',
          preview: 'c',
          tags: const [],
          favorite: false,
          updatedAt: DateTime(2026, 1, 2),
          matchSources: const {SearchMatchSource.semantic},
          semanticHitField: SemanticHitField.tags,
        ),
      ]);

      expect(summary.reminderHint, '当前结果主要由关键词命中主导，语义链路参与较弱。');
    });
  });

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
            updatedAt: DateTime(2026, 1, 2),
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

    test('builds mixed top summary with semantic quality hint when semantic results exist', () {
      final summary = buildSearchPipelineTopSummary(
        unifiedResults: [
          SearchResultItem(
            id: 'secret-1',
            type: SearchResultType.secret,
            title: 'Bank Account',
            preview: 'alice@example.com',
            tags: const ['finance'],
            favorite: false,
            updatedAt: DateTime(2026, 1, 2),
            matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
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
            updatedAt: DateTime(2026, 1, 2),
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
              updatedAt: DateTime(2026, 1, 2),
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
              updatedAt: DateTime(2026, 1, 2),
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
      expect(summary.explanation.breakdown, '前 2 条中：双命中 1 条，关键词优先 0 条，语义命中 1 条。');
      expect(summary.observability.hitBreakdown, '命中结构：双命中 1 条，关键词优先 0 条，语义命中 1 条。');
    });

    test('does not show semantic quality hint when semantic result list is empty', () {
      final summary = buildSearchPipelineTopSummary(
        unifiedResults: [
          SearchResultItem(
            id: 'secret-1',
            type: SearchResultType.secret,
            title: 'Bank Account',
            preview: 'alice@example.com',
            tags: const ['finance'],
            favorite: false,
            updatedAt: DateTime(2026, 1, 2),
            matchSources: const {SearchMatchSource.semantic},
            semanticScore: 0.96,
            semanticHitField: SemanticHitField.title,
          ),
        ],
        semanticResults: const <SemanticSearchResult>[],
      );

      expect(summary.summaryText, '当前统一结果已混合关键词与语义信号，排序会优先展示双命中内容。');
      expect(summary.showSemanticQualityHint, isFalse);
    });
  });
}
