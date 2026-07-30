part of 'search_page_test.dart';

void _registerSearchPageExplanationPrimaryCases() {
  testWidgets(
    'SearchPage renders aggregated semantic explanation as separate readable lines',
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
                  matchSources: const {SearchMatchSource.semantic},
                  semanticScore: 0.96,
                  semanticHitField: SemanticHitField.title,
                  semanticHitSummary: '标题：Bank Account；账号：alice@example.com',
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

      await _revealSearchPage(tester, find.text('• 标题：Bank Account'));

      expect(find.text('语义命中'), findsWidgets);
      expect(find.text('• 标题：Bank Account'), findsOneWidget);
      expect(find.text('• 账号：alice@example.com'), findsOneWidget);
      expect(
        find.text('命中摘要：标题：Bank Account；账号：alice@example.com'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'SearchPage shows ranking reasons for strong keyword and semantic field matches',
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
                  semanticHitSummary: '标题：Bank Account；账号：alice@example.com',
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

      await _revealSearchPage(tester, find.text('排序依据'));

      expect(find.text('排序依据'), findsOneWidget);
      expect(find.text('• 强信号：同时命中关键词与语义检索'), findsOneWidget);
      expect(find.text('• 优先查看标题，这是当前最直接的命中位置。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows assist signal label for lower-priority semantic field reasons',
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
                  title: 'Finance Note',
                  preview: 'banking tags',
                  tags: const ['banking'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                  matchSources: const {SearchMatchSource.semantic},
                  semanticScore: 0.72,
                  semanticHitField: SemanticHitField.tags,
                  semanticHitSummary: '标签：banking',
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

      await _revealSearchPage(tester, find.text('• 中信号：命中语义检索'));

      expect(find.text('• 中信号：命中语义检索'), findsOneWidget);
      expect(find.text('• 优先查看标签字段，确认标签线索是否匹配。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows keyword-only retrieval summary when semantic search is not participating',
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

      expect(find.text('当前检索链路'), findsOneWidget);
      expect(find.text('当前仅展示关键词检索结果，语义链路未参与此次结果排序。'), findsOneWidget);
      expect(find.text('结果构成：1 条关键词结果，0 条语义结果。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows mixed retrieval summary when semantic signals participate in unified results',
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
              ],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前统一结果已混合关键词与语义信号，排序会优先展示双命中内容。'), findsOneWidget);
      expect(find.text('结果构成：1 条关键词结果，1 条语义结果。'), findsOneWidget);
      expect(find.text('下方“语义匹配”区块展示的是当前语义召回明细。'), findsOneWidget);
    },
  );
}
