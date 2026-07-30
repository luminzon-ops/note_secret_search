part of 'search_page_test.dart';

void _registerSearchPageRefreshSessionCases() {
  testWidgets(
    'SearchPage shows refresh-in-progress hint and disables action while shared refresh session is active',
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
                ready: true,
                reason: '本地语义检索模型已就绪',
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => SearchIndexStatus(
                engineReady: true,
                engineReason: '索引引擎已就绪',
                hasActiveEmbeddingModel: true,
                pendingItems: [
                  SearchIndexPendingItem(
                    sourceId: 'secret-1',
                    sourceType: SearchSourceType.secret,
                    title: 'Bank Account',
                    updatedAt: DateTime(2026, 1, 2),
                    plainTextHash: 'hash-1',
                    indexPlainText: 'Bank Account',
                  ),
                ],
              ),
            ),
            searchRefreshSessionProvider.overrideWith(
              (ref) => const SearchRefreshSessionState(
                refreshing: true,
                message: '正在刷新搜索状态与结果...',
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

      await tester.pump();

      expect(find.text('正在刷新搜索状态与结果...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      final button = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('SearchPage index action uses combined refresh controller flow', (
    tester,
  ) async {
    late _RecordingSearchRefreshRunner controller;
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
              ready: true,
              reason: '本地语义检索模型已就绪',
            ),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => SearchIndexStatus(
              engineReady: true,
              engineReason: '索引引擎已就绪',
              hasActiveEmbeddingModel: true,
              pendingItems: [
                SearchIndexPendingItem(
                  sourceId: 'secret-1',
                  sourceType: SearchSourceType.secret,
                  title: 'Bank Account',
                  updatedAt: DateTime(2026, 1, 2),
                  plainTextHash: 'hash-1',
                  indexPlainText: 'Bank Account',
                ),
              ],
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
    await tester.tap(find.text('立即构建索引'));
    await tester.pump();

    expect(controller.refreshCalls, 1);
  });
}

void _registerSearchPageRefreshRecommendationCases() {
  testWidgets(
    'SearchPage shows index build recommendation when pending items exist before any completed run',
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
                ready: true,
                reason: '本地语义检索模型已就绪',
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => SearchIndexStatus(
                engineReady: true,
                engineReason: '索引引擎已就绪',
                hasActiveEmbeddingModel: true,
                pendingItems: [
                  SearchIndexPendingItem(
                    sourceId: 'secret-1',
                    sourceType: SearchSourceType.secret,
                    title: 'Bank Account',
                    updatedAt: DateTime(2026, 1, 2),
                    plainTextHash: 'hash-1',
                    indexPlainText: 'Bank Account',
                  ),
                ],
                taskState: const SearchIndexTaskState.idle(),
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

      expect(find.text('待索引内容：1 项'), findsOneWidget);
      expect(find.text('建议先构建本地索引'), findsOneWidget);
      expect(find.text('已有待索引内容，完成首次构建后再查看语义检索结果会更稳定。'), findsOneWidget);
      expect(find.text('立即构建索引'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows index refresh recommendation when new pending items exist after a completed run',
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
                ready: true,
                reason: '本地语义检索模型已就绪',
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => SearchIndexStatus(
                engineReady: true,
                engineReason: '索引引擎已就绪',
                hasActiveEmbeddingModel: true,
                pendingItems: [
                  SearchIndexPendingItem(
                    sourceId: 'note-1',
                    sourceType: SearchSourceType.note,
                    title: 'Recovery Note',
                    updatedAt: DateTime(2026, 1, 2),
                    plainTextHash: 'hash-2',
                    indexPlainText: 'Recovery Note',
                  ),
                ],
                taskState: SearchIndexTaskState(
                  running: false,
                  lastCompletedAt: DateTime(2026, 1, 1),
                  lastIndexedCount: 4,
                  lastError: null,
                ),
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

      expect(find.text('待索引内容：1 项'), findsOneWidget);
      expect(find.text('索引需要刷新'), findsOneWidget);
      expect(find.text('索引已有新变更，建议刷新后再判断当前语义检索结果。'), findsOneWidget);
      expect(find.text('刷新索引'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage can trigger combined refresh action and show success feedback',
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
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: true,
                reason: '本地语义检索模型已就绪',
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => SearchIndexStatus(
                engineReady: true,
                engineReason: '索引引擎已就绪',
                hasActiveEmbeddingModel: true,
                pendingItems: [
                  SearchIndexPendingItem(
                    sourceId: 'secret-1',
                    sourceType: SearchSourceType.secret,
                    title: 'Bank Account',
                    updatedAt: DateTime(2026, 1, 2),
                    plainTextHash: 'hash-1',
                    indexPlainText: 'Bank Account',
                  ),
                ],
                taskState: const SearchIndexTaskState.idle(),
              ),
            ),
            searchLockGuardProvider.overrideWith(
              (ref) => SearchLockGuard(accessAllowed: true),
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

      await pumpUntilFound(tester, find.text('立即构建索引'));
      await tester.tap(find.text('立即构建索引'));
      await pumpUntilFound(tester, find.text('已开始构建索引，请稍后刷新搜索结果。'));

      expect(controller.refreshCalls, 1);
      expect(find.text('已开始构建索引，请稍后刷新搜索结果。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows failure feedback when combined refresh action fails',
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
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: true,
                reason: '本地语义检索模型已就绪',
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => SearchIndexStatus(
                engineReady: true,
                engineReason: '索引引擎已就绪',
                hasActiveEmbeddingModel: true,
                pendingItems: [
                  SearchIndexPendingItem(
                    sourceId: 'note-1',
                    sourceType: SearchSourceType.note,
                    title: 'Recovery Note',
                    updatedAt: DateTime(2026, 1, 2),
                    plainTextHash: 'hash-2',
                    indexPlainText: 'Recovery Note',
                  ),
                ],
                taskState: SearchIndexTaskState(
                  running: false,
                  lastCompletedAt: DateTime(2026, 1, 1),
                  lastIndexedCount: 4,
                  lastError: null,
                ),
              ),
            ),
            refreshSearchIndexUseCaseProvider.overrideWith((ref) {
              controller = _RecordingSearchRefreshRunner(
                error: StateError('索引失败'),
              );
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
      await tester.tap(find.text('刷新索引'));
      await tester.pump();

      expect(controller.refreshCalls, 1);
      expect(find.text('索引触发失败，请稍后重试。'), findsOneWidget);
    },
  );
}
