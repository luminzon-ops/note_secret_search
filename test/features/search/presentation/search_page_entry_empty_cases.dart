part of 'search_page_test.dart';

void _registerSearchPageEntryCases() {
  testWidgets(
    'SearchPage shows settings entry and does not render inline settings cards',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
          GoRoute(
            path: '/search/settings',
            builder: (context, state) =>
                const Scaffold(body: Text('settings target')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedSearchResultsProvider.overrideWith(
              (ref) async => const <SearchResultItem>[],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('搜索设置与索引'), findsOneWidget);
      expect(find.text('检索范围控制'), findsNothing);
      expect(find.text('语义索引设置'), findsNothing);

      await tester.tap(find.text('搜索设置与索引'));
      await tester.pumpAndSettle();

      expect(find.text('settings target'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage empty feedback routes users to model management when runtime is unverified',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
          GoRoute(
            path: '/models',
            builder: (context, state) =>
                const Scaffold(body: Text('models target')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchQueryProvider.overrideWith((ref) => 'bank'),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '待校验',
                runtimeStatus: EmbeddingRuntimeStatus.installedUnverified,
              ),
            ),
            unifiedSearchResultsProvider.overrideWith(
              (ref) async => const <SearchResultItem>[],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前语义模型已安装但尚未完成运行时校验，本次还无法参与语义检索。'), findsOneWidget);
      expect(find.text('前往模型管理'), findsOneWidget);

      await tester.tap(find.text('前往模型管理'));
      await tester.pumpAndSettle();

      expect(find.text('models target'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows blocked runtime action label for degraded readiness',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: 'runtime broken',
                runtimeStatus: EmbeddingRuntimeStatus.degraded,
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => const SearchIndexStatus(
                engineReady: false,
                engineReason: 'runtime broken',
                hasActiveEmbeddingModel: true,
                pendingItems: <SearchIndexPendingItem>[],
              ),
            ),
            unifiedSearchResultsProvider.overrideWith(
              (ref) async => const <SearchResultItem>[],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('本地语义链路未就绪'), findsOneWidget);
      expect(find.text('前往模型管理排查'), findsOneWidget);
    },
  );
}

void _registerSearchPageEmptyCases() {
  testWidgets(
    'SearchPage shows empty-query guidance before the user starts searching',
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
              (ref) async => const <SearchResultItem>[],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('输入关键词、标签或语义描述后，这里会开始展示检索结果。'), findsOneWidget);
      expect(find.text('你也可以先前往“搜索设置与索引”调整检索范围或索引策略。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows no-result guidance when query has no matches and semantic search is not participating',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
            searchQueryProvider.overrideWith((ref) => 'bank account'),
            unifiedSearchResultsProvider.overrideWith(
              (ref) async => const <SearchResultItem>[],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前查询暂无命中结果。'), findsOneWidget);
      expect(find.text('本次未找到匹配结果，建议检查检索范围、查询词，或刷新索引后再试。'), findsOneWidget);
      expect(find.text('前往搜索设置与索引'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage no-result guidance action can navigate to search settings',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
          GoRoute(
            path: '/search/settings',
            builder: (context, state) =>
                const Scaffold(body: Text('settings target')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
            searchQueryProvider.overrideWith((ref) => 'bank account'),
            unifiedSearchResultsProvider.overrideWith(
              (ref) async => const <SearchResultItem>[],
            ),
            semanticSearchResultsProvider.overrideWith(
              (ref) async => const <SemanticSearchResult>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('前往搜索设置与索引'));
      await tester.pumpAndSettle();

      expect(find.text('settings target'), findsOneWidget);
    },
  );
}
