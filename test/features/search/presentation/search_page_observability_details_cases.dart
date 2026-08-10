part of 'search_page_test.dart';

void _registerSearchPageObservabilityDetailCases() {
  testWidgets(
    'SearchPage shows reminder hint in observability summary when semantic participation is assist-field driven',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedSearchResultsProvider.overrideWith(
              (ref) async => [
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
                  semanticHitSummary: '标签：backup',
                ),
                SearchResultItem(
                  id: 'note-2',
                  type: SearchResultType.note,
                  title: 'Codes Note',
                  preview: 'body hit',
                  tags: const ['codes'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                  matchSources: const {SearchMatchSource.semantic},
                  semanticScore: 0.71,
                  semanticHitField: SemanticHitField.noteBody,
                  semanticHitSummary: '正文：codes',
                ),
              ],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前语义参与主要来自辅助字段，建议谨慎判断结果质量。'), findsOneWidget);
    },
  );

  testWidgets('SearchPage keeps observability summary compact by default', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {
                  SearchMatchSource.keyword,
                  SearchMatchSource.semantic,
                },
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
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
                semanticHitSummary: '标签：backup',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await _revealSearchPage(tester, find.widgetWithText(TextButton, '展开更多观测'));
    expect(find.textContaining('命中结构：'), findsOneWidget);
    expect(find.text('展开更多观测'), findsOneWidget);

    expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsNothing);
    expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsNothing);
    expect(find.text('当前语义命中主要集中在正文字段（1 条）。'), findsNothing);
  });

  testWidgets(
    'SearchPage can expand and collapse secondary observability diagnostics',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedSearchResultsProvider.overrideWith(
              (ref) async => [
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
                  semanticHitSummary: '标签：backup',
                  evidence: [
                    SearchEvidence(
                      kind: SearchEvidenceKind.semantic,
                      sourceField: SearchSourceField.noteTags,
                      fieldChunkIndex: 0,
                      summary: '标签：backup',
                      rawSimilarity: 0.93,
                      weight: 0.96,
                      rankingScore: 0.8928,
                      threshold: 0.90,
                      modelRevisionHash: 'a' * 64,
                      fingerprintVersion: 1,
                      indexConfigVersion: 2,
                      indexConfigEpoch: 7,
                      chunkSchemaVersion: 1,
                      vectorFormatVersion: 1,
                    ),
                  ],
                ),
                SearchResultItem(
                  id: 'note-2',
                  type: SearchResultType.note,
                  title: 'Codes Note',
                  preview: 'body hit',
                  tags: const ['codes'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                  matchSources: const {SearchMatchSource.semantic},
                  semanticScore: 0.71,
                  semanticHitField: SemanticHitField.noteBody,
                  semanticHitSummary: '正文：codes',
                  evidence: [
                    SearchEvidence(
                      kind: SearchEvidenceKind.semantic,
                      sourceField: SearchSourceField.noteBody,
                      fieldChunkIndex: 0,
                      summary: '正文：codes',
                      rawSimilarity: 0.91,
                      weight: 0.92,
                      rankingScore: 0.8372,
                      threshold: 0.90,
                      modelRevisionHash: 'a' * 64,
                      fingerprintVersion: 1,
                      indexConfigVersion: 2,
                      indexConfigEpoch: 7,
                      chunkSchemaVersion: 1,
                      vectorFormatVersion: 1,
                    ),
                  ],
                ),
              ],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsNothing);
      expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsNothing);
      expect(
        find.text('索引版本：指纹 v1，配置 v2/e7，分块 v1，向量 v1；模型修订 1 组。'),
        findsNothing,
      );
      expect(find.text('当前语义命中主要集中在正文字段（1 条）。'), findsNothing);

      await _revealAndTapSearchPage(
        tester,
        find.widgetWithText(TextButton, '展开更多观测'),
      );
      await tester.pumpAndSettle();

      expect(find.text('收起观测详情'), findsOneWidget);
      expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsOneWidget);
      expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsOneWidget);
      expect(
        find.text('索引版本：指纹 v1，配置 v2/e7，分块 v1，向量 v1；模型修订 1 组。'),
        findsOneWidget,
      );
      expect(find.textContaining('a' * 64), findsNothing);
      expect(find.text('当前语义命中主要集中在正文字段（1 条）。'), findsOneWidget);

      await _revealAndTapSearchPage(
        tester,
        find.widgetWithText(TextButton, '收起观测详情'),
      );
      await tester.pumpAndSettle();

      expect(find.text('展开更多观测'), findsOneWidget);
      expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsNothing);
      expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsNothing);
      expect(
        find.text('索引版本：指纹 v1，配置 v2/e7，分块 v1，向量 v1；模型修订 1 组。'),
        findsNothing,
      );
      expect(find.text('当前语义命中主要集中在正文字段（1 条）。'), findsNothing);
    },
  );
}
