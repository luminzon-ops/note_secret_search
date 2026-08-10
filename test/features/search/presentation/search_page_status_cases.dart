part of 'search_page_test.dart';

void _registerSearchPageStatusCases() {
  testWidgets(
    'SearchPage shows aligned ready status when semantic pipeline is available',
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
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: true,
                reason: '本地语义检索模型已就绪：MiniLM Embedding',
                activeEmbeddingModel: ModelRegistryEntry(
                  id: 'embed-1',
                  type: 'embedding',
                  provider: 'builtin',
                  name: 'MiniLM Embedding',
                  version: '1.0',
                  sizeBytes: 1024,
                  quantization: 'Q8',
                  minRamMb: 512,
                  recommendedTier: 'mvp',
                  localPath: '/data/models/minilm.onnx',
                  checksum: 'abc',
                  enabled: true,
                  installedAt: null,
                  filePresent: true,
                ),
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => SearchIndexStatus(
                engineReady: true,
                engineReason: '索引引擎已就绪',
                hasActiveEmbeddingModel: true,
                pendingItems: const <SearchIndexPendingItem>[],
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

      expect(find.text('本地语义检索已可用'), findsOneWidget);
      expect(find.text('本地语义检索模型已就绪：MiniLM Embedding'), findsOneWidget);
      expect(find.text('前往搜索设置与索引'), findsNothing);
    },
  );

  testWidgets(
    'SearchPage shows aligned blocked semantic pipeline state with quick entry to model management',
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
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '尚未选择可用的本地 embedding 模型。',
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => const SearchIndexStatus(
                engineReady: false,
                engineReason: '索引引擎未就绪',
                hasActiveEmbeddingModel: false,
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
      expect(find.text('尚未选择可用的本地 embedding 模型。'), findsOneWidget);
      expect(find.text('前往模型管理'), findsOneWidget);

      await tester.tap(find.text('前往模型管理'));
      await tester.pumpAndSettle();

      expect(find.text('models target'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchPage shows aligned blocked status and model-management action',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SearchPage()),
          GoRoute(
            path: '/models',
            builder: (context, state) =>
                const Scaffold(body: Text('models page')),
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
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '缺少可用 embedding 模型',
              ),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => const SearchIndexStatus(
                engineReady: false,
                engineReason: '索引引擎未就绪',
                hasActiveEmbeddingModel: false,
                pendingItems: <SearchIndexPendingItem>[],
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('本地语义链路未就绪'), findsOneWidget);
      expect(find.text('缺少可用 embedding 模型'), findsOneWidget);
      expect(find.text('前往模型管理'), findsOneWidget);
    },
  );

  testWidgets('SearchPage shows aligned initial-index status and action', (
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
            (ref) async => const <SearchResultItem>[],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('建议先构建本地索引'), findsOneWidget);
    expect(find.text('立即构建索引'), findsOneWidget);
  });

  testWidgets('SearchPage shows aligned refresh status and action', (
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
            (ref) async => const <SearchResultItem>[],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('索引需要刷新'), findsOneWidget);
    expect(find.text('刷新索引'), findsOneWidget);
  });

  testWidgets('SearchPage shows aligned failure status and retry action', (
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
            (ref) async => const <SearchResultItem>[],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
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
              pendingItems: const <SearchIndexPendingItem>[],
              taskState: SearchIndexTaskState(
                running: false,
                lastCompletedAt: DateTime(2026, 1, 1),
                lastIndexedCount: 0,
                lastError: 'disk full',
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('最近一次索引失败'), findsOneWidget);
    expect(find.text('重试索引'), findsOneWidget);
    expect(find.text('disk full'), findsOneWidget);
  });

  testWidgets('SearchPage shows aligned ready state without build prompts', (
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
            (ref) async => const <SearchResultItem>[],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
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
              pendingItems: const <SearchIndexPendingItem>[],
              taskState: SearchIndexTaskState(
                running: false,
                lastCompletedAt: DateTime(2026, 1, 1),
                lastIndexedCount: 4,
                lastError: null,
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('本地语义检索已可用'), findsOneWidget);
    expect(find.text('本地语义检索模型已就绪'), findsOneWidget);
    expect(find.text('立即构建索引'), findsNothing);
    expect(find.text('刷新索引'), findsNothing);
  });
}
