part of 'search_page_test.dart';

void _registerSearchPageResultStructureCase() {
  testWidgets(
    'SearchPage shows result overview and splits unified results into secret and note sections',
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
                  matchSources: const {SearchMatchSource.keyword},
                ),
                SearchResultItem(
                  id: 'note-1',
                  type: SearchResultType.note,
                  title: 'Recovery Note',
                  preview: 'backup codes',
                  tags: const ['backup'],
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

      await tester.scrollUntilVisible(
        find.text('结果概览：共 2 条，密码 1 条，笔记 1 条。'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('结果概览：共 2 条，密码 1 条，笔记 1 条。'), findsOneWidget);
      expect(find.text('密码结果'), findsOneWidget);
      expect(find.text('笔记结果'), findsOneWidget);
      expect(find.text('Bank Account'), findsOneWidget);
      expect(find.text('Recovery Note'), findsOneWidget);
    },
  );
}

void _registerSearchPageResultSummaryCases() {
  testWidgets('SearchPage shows dual-hit dominant overview summary', (
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
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'a',
                type: SearchResultType.secret,
                title: 'A',
                preview: 'a',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {
                  SearchMatchSource.keyword,
                  SearchMatchSource.semantic,
                },
              ),
              SearchResultItem(
                id: 'b',
                type: SearchResultType.secret,
                title: 'B',
                preview: 'b',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {
                  SearchMatchSource.keyword,
                  SearchMatchSource.semantic,
                },
              ),
              SearchResultItem(
                id: 'c',
                type: SearchResultType.note,
                title: 'C',
                preview: 'c',
                tags: const [],
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

    expect(find.text('当前前排结果以双命中为主，关键词与语义信号共同参与排序。'), findsOneWidget);
    expect(find.text('前 3 条中：双命中 2 条，关键词优先 1 条，语义命中 0 条。'), findsOneWidget);
  });

  testWidgets(
    'SearchPage shows keyword-dominant overview when semantic only assists',
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
                  type: SearchResultType.secret,
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
                ),
              ],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => [
                SemanticSearchResult(
                  item: SearchResultItem(
                    id: 'c',
                    type: SearchResultType.note,
                    title: 'C',
                    preview: 'c',
                    tags: const [],
                    favorite: false,
                    updatedAt: DateTime(2026, 1, 2),
                  ),
                  score: 0.76,
                  hitSummary: '标题：C',
                  hitField: SemanticHitField.title,
                ),
              ],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前前排结果以关键词命中为主，语义信号主要用于补充排序。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows semantic-dominant overview when semantic-assisted results lead',
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
                  id: 'a',
                  type: SearchResultType.secret,
                  title: 'A',
                  preview: 'a',
                  tags: const [],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                  matchSources: const {SearchMatchSource.semantic},
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
                ),
              ],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => [
                SemanticSearchResult(
                  item: SearchResultItem(
                    id: 'a',
                    type: SearchResultType.secret,
                    title: 'A',
                    preview: 'a',
                    tags: const [],
                    favorite: false,
                    updatedAt: DateTime(2026, 1, 2),
                  ),
                  score: 0.88,
                  hitSummary: '标题：A',
                  hitField: SemanticHitField.title,
                ),
                SemanticSearchResult(
                  item: SearchResultItem(
                    id: 'b',
                    type: SearchResultType.note,
                    title: 'B',
                    preview: 'b',
                    tags: const [],
                    favorite: false,
                    updatedAt: DateTime(2026, 1, 2),
                  ),
                  score: 0.81,
                  hitSummary: '标题：B',
                  hitField: SemanticHitField.title,
                ),
              ],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前前排结果更多依赖语义召回，适合继续检查命中摘要与上下文。'), findsOneWidget);
    },
  );

  testWidgets('SearchPage shows dual-hit chip on mixed-match results', (
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
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'a',
                type: SearchResultType.secret,
                title: 'A',
                preview: 'a',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {
                  SearchMatchSource.keyword,
                  SearchMatchSource.semantic,
                },
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

    await tester.scrollUntilVisible(
      find.text('双命中'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('双命中'), findsOneWidget);
  });

  testWidgets('SearchPage shows keyword-primary and semantic-assist chips', (
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
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
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
                matchSources: const {SearchMatchSource.semantic},
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

    await tester.scrollUntilVisible(
      find.text('关键词优先'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('关键词优先'), findsOneWidget);
    expect(find.text('语义命中'), findsOneWidget);
  });
}
