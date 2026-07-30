part of 'search_page_test.dart';

void _registerSearchPageHandoffCases() {
  testWidgets(
    'SearchPage shows refresh completion feedback when query matches feedback context',
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
            searchRefreshFeedbackProvider.overrideWith(
              (ref) => const SearchRefreshFeedbackState(
                visible: true,
                headline: '搜索状态已刷新',
                message: '当前结果已更新，结果数量从 1 条变为 3 条。',
                changed: true,
                queryAtRefresh: 'bank',
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

      expect(find.text('搜索状态已刷新'), findsOneWidget);
      expect(find.text('当前结果已更新，结果数量从 1 条变为 3 条。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows pending-reindex handoff card when settings were saved without refreshing index',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchPendingReindexHandoffProvider.overrideWith(
              (ref) => const SearchPendingReindexHandoffState(
                visible: true,
                message: '你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。',
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

      expect(find.text('设置已保存，但语义结果还没刷新'), findsOneWidget);
      expect(find.text('你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。'), findsOneWidget);
      expect(find.text('立即刷新索引'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage pending-reindex handoff action triggers refresh flow',
    (tester) async {
      late _RecordingSearchRefreshRunner controller;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchPendingReindexHandoffProvider.overrideWith(
              (ref) => const SearchPendingReindexHandoffState(
                visible: true,
                message: '你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。',
              ),
            ),
            refreshSearchIndexUseCaseProvider.overrideWith((ref) {
              controller = _RecordingSearchRefreshRunner();
              return controller;
            }),
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
      await tester.tap(find.text('立即刷新索引'));
      await tester.pump();

      expect(controller.refreshCalls, 1);
    },
  );

  testWidgets(
    'SearchPage clears pending-reindex handoff card after refresh starts successfully',
    (tester) async {
      late _RecordingSearchRefreshRunner controller;
      final container = ProviderContainer(
        overrides: [
          searchRefreshControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchRefreshRunner();
            return _handoffRefreshController(controller);
          }),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => const <SearchResultItem>[],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('立即刷新索引'));
      await tester.pumpAndSettle();

      expect(controller.refreshCalls, 1);
      expect(find.text('设置已保存，但语义结果还没刷新'), findsNothing);
      expect(
        container.read(searchPendingReindexHandoffProvider).visible,
        isFalse,
      );
    },
  );

  testWidgets(
    'SearchPage keeps pending-reindex handoff card when refresh trigger fails',
    (tester) async {
      late _RecordingSearchRefreshRunner controller;
      final container = ProviderContainer(
        overrides: [
          searchRefreshControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchRefreshRunner(
              error: StateError('refresh failed'),
            );
            return _handoffRefreshController(controller);
          }),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => const <SearchResultItem>[],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('立即刷新索引'));
      await tester.pumpAndSettle();

      expect(controller.refreshCalls, 1);
      expect(find.text('设置已保存，但语义结果还没刷新'), findsOneWidget);
      expect(
        container.read(searchPendingReindexHandoffProvider).visible,
        isTrue,
      );
    },
  );

  testWidgets(
    'SearchPage does not show pending-reindex handoff card when no handoff state exists',
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

      expect(find.text('设置已保存，但语义结果还没刷新'), findsNothing);
    },
  );
}

void _registerSearchPageFeedbackMismatchCase() {
  testWidgets(
    'SearchPage hides refresh completion feedback when current query no longer matches',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchQueryProvider.overrideWith((ref) => 'email'),
            searchRefreshFeedbackProvider.overrideWith(
              (ref) => const SearchRefreshFeedbackState(
                visible: true,
                headline: '搜索状态已刷新',
                message: '当前结果已更新，本轮刷新未改变当前结果。',
                changed: false,
                queryAtRefresh: 'bank',
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

      expect(find.text('搜索状态已刷新'), findsNothing);
      expect(find.text('当前结果已更新，本轮刷新未改变当前结果。'), findsNothing);
    },
  );
}
