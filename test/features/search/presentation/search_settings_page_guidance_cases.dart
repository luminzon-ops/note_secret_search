part of 'search_settings_page_test.dart';

void _runSearchSettingsGuidanceCases() {
  testWidgets(
    'SearchSettingsPage blocked guidance can navigate to model management',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const SearchSettingsPage(),
          ),
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
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig(
                includeTitle: true,
                includeSecretNote: true,
                includePasswordField: false,
                includeUsername: true,
                includeUrl: true,
                includeTags: true,
                includeNoteBody: true,
                allowLocalEmbedding: false,
                allowExternalProviderAccess: false,
              ),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '本地语义检索已关闭',
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
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('前往模型管理选择语义模型'));
      await tester.pumpAndSettle();

      expect(find.text('models page'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows build-index guidance when pending items are actionable',
    (tester) async {
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'secret-1',
        sourceType: SearchSourceType.secret,
        title: '邮箱账号',
        updatedAt: DateTime(2026, 4, 21, 10, 0),
        plainTextHash: 'hash-1',
        indexPlainText: '邮箱账号\nuser@example.com',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '存在待构建索引项',
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
                pendingItems: [pendingItem],
              ),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
          ],
          child: const MaterialApp(home: SearchSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('待索引摘要：密码 1 项'), findsOneWidget);
      expect(find.text('最近变更项'), findsOneWidget);
      expect(find.text('下一步可执行操作'), findsOneWidget);
      expect(find.text('立即构建索引'), findsWidgets);
      expect(find.text('刷新本地索引'), findsNothing);
    },
  );

  testWidgets(
    'SearchSettingsPage shows mixed pending item summary for secrets and notes',
    (tester) async {
      final secretPendingItem = SearchIndexPendingItem(
        sourceId: 'secret-1',
        sourceType: SearchSourceType.secret,
        title: '邮箱账号',
        updatedAt: DateTime(2026, 4, 21, 10, 0),
        plainTextHash: 'hash-1',
        indexPlainText: '邮箱账号\nuser@example.com',
      );
      final notePendingItem = SearchIndexPendingItem(
        sourceId: 'note-1',
        sourceType: SearchSourceType.note,
        title: '恢复码备忘',
        updatedAt: DateTime(2026, 4, 21, 11, 0),
        plainTextHash: 'hash-2',
        indexPlainText: '恢复码备忘\nsummary',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '存在待构建索引项',
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
                pendingItems: [secretPendingItem, notePendingItem],
              ),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
          ],
          child: const MaterialApp(home: SearchSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('待索引摘要：密码 1 项，笔记 1 项'), findsOneWidget);
      expect(find.text('最近变更项'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows refresh-index guidance after a prior completed index run',
    (tester) async {
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'note-1',
        sourceType: SearchSourceType.note,
        title: '恢复码备忘',
        updatedAt: DateTime(2026, 4, 21, 11, 0),
        plainTextHash: 'hash-2',
        indexPlainText: '恢复码备忘\nsummary',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '索引需要刷新',
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
                pendingItems: [pendingItem],
                taskState: SearchIndexTaskState(
                  running: false,
                  lastCompletedAt: DateTime(2026, 4, 21, 9, 30),
                  lastIndexedCount: 4,
                  lastError: null,
                ),
              ),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
          ],
          child: const MaterialApp(home: SearchSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('刷新索引'), findsWidgets);
      expect(find.text('立即构建索引'), findsNothing);
    },
  );

  testWidgets(
    'SearchSettingsPage explains that index is up to date after a successful run with no pending items',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: true,
                reason: '本地语义检索可用',
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
                  lastCompletedAt: DateTime(2026, 4, 21, 9, 30),
                  lastIndexedCount: 4,
                  lastError: null,
                ),
              ),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
          ],
          child: const MaterialApp(home: SearchSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('当前状态：本地语义检索已可用'), findsOneWidget);
      expect(find.text('当前索引已最新，可以直接继续使用语义检索。'), findsWidgets);
      expect(find.text('待索引摘要：暂无待处理项'), findsOneWidget);
    },
  );
}
