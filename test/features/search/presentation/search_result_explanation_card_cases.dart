part of 'search_result_explanation_test.dart';

void _runSearchResultCardExplanationCases() {
  group('buildSearchResultCardExplanation', () {
    test(
      'returns dual high-quality explanation for dual-hit high-quality semantic result',
      () {
        final explanation = buildSearchResultCardExplanation(
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
            semanticHitField: SemanticHitField.title,
          ),
        );

        expect(explanation, '这条结果同时命中关键词与重点语义字段，可优先查看。');
      },
    );

    test(
      'returns dual assist explanation for dual-hit assist semantic result',
      () {
        final explanation = buildSearchResultCardExplanation(
          SearchResultItem(
            id: 'note-1',
            type: SearchResultType.note,
            title: 'Recovery Note',
            preview: 'backup tags',
            tags: const ['backup'],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {
              SearchMatchSource.keyword,
              SearchMatchSource.semantic,
            },
            semanticHitField: SemanticHitField.tags,
          ),
        );

        expect(explanation, '这条结果同时命中关键词，语义部分主要提供补充线索，建议结合预览确认。');
      },
    );

    test('returns keyword-primary explanation for keyword-only result', () {
      final explanation = buildSearchResultCardExplanation(
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
      );

      expect(explanation, '这条结果主要由关键词命中进入结果。');
    });

    test(
      'returns semantic high-quality explanation for semantic-only high-quality result',
      () {
        final explanation = buildSearchResultCardExplanation(
          SearchResultItem(
            id: 'secret-3',
            type: SearchResultType.secret,
            title: 'Vault Account',
            preview: 'vault@example.com',
            tags: const ['vault'],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.semantic},
            semanticHitField: SemanticHitField.summary,
          ),
        );

        expect(explanation, '这条结果主要由重点语义命中支持，适合优先检查。');
      },
    );

    test(
      'returns semantic assist explanation for semantic-only assist result',
      () {
        final explanation = buildSearchResultCardExplanation(
          SearchResultItem(
            id: 'note-2',
            type: SearchResultType.note,
            title: 'Codes Note',
            preview: 'body hit',
            tags: const ['codes'],
            favorite: false,
            updatedAt: _searchResultTimestamp,
            matchSources: const {SearchMatchSource.semantic},
            semanticHitField: SemanticHitField.noteBody,
          ),
        );

        expect(explanation, '这条结果主要由补充语义线索召回，建议继续确认。');
      },
    );
  });
}
