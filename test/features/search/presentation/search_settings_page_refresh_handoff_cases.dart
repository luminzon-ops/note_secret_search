part of 'search_settings_page_test.dart';

void _runSearchSettingsRefreshHandoffCases() {
  testWidgets('SearchSettingsPage index guidance triggers pending indexing', (
    tester,
  ) async {
    late _RecordingSearchRefreshRunner runner;
    final pendingItem = SearchIndexPendingItem(
      sourceId: 'secret-1',
      sourceType: SearchSourceType.secret,
      title: '邮箱账号',
      updatedAt: DateTime(2026, 4, 21, 10, 0),
      plainTextHash: 'hash-4',
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
          refreshSearchIndexUseCaseProvider.overrideWith((ref) {
            runner = _RecordingSearchRefreshRunner();
            return runner;
          }),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await revealAndTap(tester, find.widgetWithText(ActionChip, '立即构建索引'));
    await tester.pump();

    expect(runner.refreshCalls, 1);
  });

  testWidgets(
    'SearchSettingsPage shows success feedback after triggering index build',
    (tester) async {
      late _RecordingSearchRefreshRunner runner;
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'secret-1',
        sourceType: SearchSourceType.secret,
        title: '邮箱账号',
        updatedAt: DateTime(2026, 4, 21, 10, 0),
        plainTextHash: 'hash-success-feedback',
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
            searchLockGuardProvider.overrideWith(
              (ref) => SearchLockGuard(accessAllowed: true),
            ),
            refreshSearchIndexUseCaseProvider.overrideWith((ref) {
              runner = _RecordingSearchRefreshRunner();
              return runner;
            }),
          ],
          child: const MaterialApp(home: SearchSettingsPage()),
        ),
      );

      final indexAction = find.widgetWithText(ActionChip, '立即构建索引');
      await pumpUntilFound(tester, indexAction);
      await revealAndTap(tester, indexAction);
      await pumpUntilFound(tester, find.text('已开始处理待索引内容，请稍后查看最新结果。'));

      expect(runner.refreshCalls, 1);
      expect(find.text('已开始处理待索引内容，请稍后查看最新结果。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows failure feedback after triggering index build',
    (tester) async {
      late _RecordingSearchRefreshRunner runner;
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'secret-1',
        sourceType: SearchSourceType.secret,
        title: '邮箱账号',
        updatedAt: DateTime(2026, 4, 21, 10, 0),
        plainTextHash: 'hash-failure-feedback',
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
            refreshSearchIndexUseCaseProvider.overrideWith((ref) {
              runner = _RecordingSearchRefreshRunner(error: StateError('索引失败'));
              return runner;
            }),
          ],
          child: const MaterialApp(home: SearchSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();
      await revealAndTap(tester, find.widgetWithText(ActionChip, '立即构建索引'));
      await tester.pump();

      expect(runner.refreshCalls, 1);
      expect(find.text('索引触发失败，请稍后重试。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows no-pending feedback when index can run but nothing needs processing',
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
              (ref) async => const SearchIndexStatus(
                engineReady: true,
                engineReason: '索引引擎已就绪',
                hasActiveEmbeddingModel: true,
                pendingItems: <SearchIndexPendingItem>[],
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

      expect(find.text('当前索引已最新，可以直接继续使用语义检索。'), findsOneWidget);
    },
  );
}
