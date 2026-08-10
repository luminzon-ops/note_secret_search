part of 'search_page_test.dart';

void _registerSearchPageSemanticTierCases() {
  testWidgets(
    'SearchPage shows semantic tier counts in the top summary when semantic signals are present',
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
                  semanticHitSummary: '标题：Bank Account',
                ),
                SearchResultItem(
                  id: 'secret-2',
                  type: SearchResultType.secret,
                  title: 'Vault Account',
                  preview: 'vault@example.com',
                  tags: const ['vault'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                  matchSources: const {SearchMatchSource.semantic},
                  semanticScore: 0.91,
                  semanticHitField: SemanticHitField.summary,
                  semanticHitSummary: '摘要：Vault Account',
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

      expect(
        find.textContaining('当前语义结果中，重点语义命中 2 条，补充语义线索 0 条。'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SearchPage shows high-quality semantic explanation for title-based semantic hits',
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
                  semanticHitSummary: '标题：Bank Account',
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

      expect(find.text('• 重点语义命中：标题属于高可信语义字段'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows assist semantic explanation for lower-priority semantic fields',
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
      await _revealSearchPage(tester, find.text('排序依据'));

      expect(find.text('• 补充语义线索：标签属于补充语义线索'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage does not show semantic tiering copy for keyword-only results',
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

      expect(find.textContaining('重点语义命中'), findsNothing);
      expect(find.textContaining('补充语义线索'), findsNothing);
    },
  );
}

void _registerSearchPageQualityHintCase() {
  testWidgets(
    'SearchPage shows semantic quality gate hint when semantic signals participate in unified results',
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

      expect(find.text('当前语义结果仅展示通过最低质量门槛的命中。'), findsOneWidget);
    },
  );
}

void _registerSearchPageResultExplanationCase() {
  testWidgets(
    'SearchPage shows result-card explanation for high-quality dual-hit result',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchQueryProvider.overrideWith((ref) => 'bank'),
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
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();
      await _revealSearchPage(tester, find.text('这条结果同时命中关键词与重点语义字段，可优先查看。'));

      expect(find.text('这条结果同时命中关键词与重点语义字段，可优先查看。'), findsOneWidget);
    },
  );
}
