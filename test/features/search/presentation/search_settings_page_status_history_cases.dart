part of 'search_settings_page_test.dart';

void _runSearchSettingsStatusHistoryCases() {
  testWidgets(
    'SearchSettingsPage explains that index refresh is needed when new pending items exist after a successful run',
    (tester) async {
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'note-1',
        sourceType: SearchSourceType.note,
        title: '恢复码备忘',
        updatedAt: DateTime(2026, 4, 21, 11, 0),
        plainTextHash: 'hash-refresh',
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

      expect(find.text('当前状态：索引需要刷新'), findsOneWidget);
      expect(find.text('索引已有新变更，建议刷新后再判断当前语义检索结果。'), findsWidgets);
    },
  );

  testWidgets(
    'SearchSettingsPage explains latest indexing failure when last run errored',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '最近一次索引失败',
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
                  lastIndexedCount: 0,
                  lastError: '磁盘空间不足',
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

      expect(find.text('当前状态：最近一次索引失败'), findsOneWidget);
      expect(find.text('索引任务未成功完成，建议先重试索引再判断语义检索效果。'), findsWidgets);
      expect(find.text('磁盘空间不足'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage explains first-time index build when pending items exist but no run has completed',
    (tester) async {
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'secret-1',
        sourceType: SearchSourceType.secret,
        title: '邮箱账号',
        updatedAt: DateTime(2026, 4, 21, 10, 0),
        plainTextHash: 'hash-first-run',
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

      expect(find.text('当前状态：建议先构建本地索引'), findsOneWidget);
      expect(find.text('已有待索引内容，完成首次构建后再查看语义检索结果会更稳定。'), findsWidgets);
    },
  );

  testWidgets(
    'SearchSettingsPage shows running-state summary while indexing is in progress',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(
                ready: false,
                reason: '正在构建索引',
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
              (ref) async => const SearchIndexStatus(
                engineReady: true,
                engineReason: '索引引擎已就绪',
                hasActiveEmbeddingModel: true,
                pendingItems: <SearchIndexPendingItem>[],
                taskState: SearchIndexTaskState(
                  running: true,
                  lastCompletedAt: null,
                  lastIndexedCount: 0,
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

      await tester.pump();

      expect(find.text('自动索引中'), findsOneWidget);
      expect(find.text('当前状态：正在构建索引'), findsOneWidget);
      expect(find.text('系统正在处理待索引内容，完成后会自动刷新这里的摘要。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows latest run summary when a prior indexing run completed',
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

      expect(find.text('最近结果摘要'), findsOneWidget);
      expect(find.text('最近一次完成 4 项，当前无错误。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage does not show index guidance when indexing is not actionable',
    (tester) async {
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'secret-1',
        sourceType: SearchSourceType.secret,
        title: '邮箱账号',
        updatedAt: DateTime(2026, 4, 21, 10, 0),
        plainTextHash: 'hash-3',
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
                reason: '索引引擎未就绪',
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
                engineReady: false,
                engineReason: '索引引擎未就绪',
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

      expect(find.text('立即构建索引'), findsNothing);
      expect(find.text('刷新已有本地索引'), findsNothing);
    },
  );
}
