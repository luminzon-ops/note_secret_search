part of 'search_page_test.dart';

void _registerSearchPageObservabilityPrimaryCases() {
  testWidgets(
    'SearchPage shows observability summary for mixed search result composition',
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
              ],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => [
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
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      await _revealAndTapSearchPage(
        tester,
        find.widgetWithText(TextButton, '展开更多观测'),
      );
      await tester.pumpAndSettle();

      expect(find.text('搜索观测摘要'), findsOneWidget);
      expect(find.text('命中结构：双命中 0 条，关键词优先 1 条，语义命中 2 条。'), findsOneWidget);
      expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsOneWidget);
      expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows semantic-only filtering stats in observability summary',
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
                  id: 'dual',
                  type: SearchResultType.secret,
                  title: 'Dual Result',
                  preview: 'dual preview',
                  tags: const ['finance'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                  matchSources: const {
                    SearchMatchSource.keyword,
                    SearchMatchSource.semantic,
                  },
                  semanticScore: 0.96,
                  semanticHitField: SemanticHitField.title,
                  semanticHitSummary: '标题：Dual Result',
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
                  semanticHitSummary: '摘要：Kept Semantic',
                ),
              ],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => [
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
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      await _revealAndTapSearchPage(
        tester,
        find.widgetWithText(TextButton, '展开更多观测'),
      );
      await tester.pumpAndSettle();

      expect(find.text('语义过滤：语义直达候选 3 条，保留 1 条，过滤 2 条。'), findsOneWidget);
      expect(find.text('过滤原因：低质量补充语义线索 2 条，结果上限截断 0 条。'), findsOneWidget);
      expect(find.text('Filtered 1'), findsNothing);
      expect(find.text('Filtered 2'), findsNothing);
    },
  );

  testWidgets(
    'SearchPage hides observability field distribution when no semantic fields participate',
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
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('搜索观测摘要'), findsOneWidget);
      expect(find.text('命中结构：双命中 0 条，关键词优先 1 条，语义命中 0 条。'), findsOneWidget);
      expect(find.textContaining('字段分布：'), findsNothing);
    },
  );

  testWidgets(
    'SearchPage shows dominant signal and dominant field hints in observability summary',
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

      await _revealSearchPage(tester, find.text('当前结果主要由双命中主导（1 条）。'));
      expect(find.text('当前结果主要由双命中主导（1 条）。'), findsOneWidget);
      await _revealAndTapSearchPage(
        tester,
        find.widgetWithText(TextButton, '展开更多观测'),
      );
      await tester.pumpAndSettle();

      expect(find.text('当前语义命中主要集中在标题字段（1 条）。'), findsOneWidget);
    },
  );
}
