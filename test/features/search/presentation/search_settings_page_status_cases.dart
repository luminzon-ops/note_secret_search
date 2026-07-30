part of 'search_settings_page_test.dart';

void _runSearchSettingsStatusCases() {
  testWidgets(
    'SearchSettingsPage shows search scope, semantic status, and index settings sections',
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

      expect(find.text('搜索与索引设置'), findsOneWidget);
      expect(find.text('本地语义检索已可用'), findsOneWidget);
      expect(find.text('当前语义链路能力'), findsOneWidget);
      expect(find.text('MiniLM Embedding'), findsOneWidget);
      expect(
        find.text(
          'builtin · embedding · Q8 · 版本 1.0 · 0.0 MB · RAM ≥ 512MB · 推荐档位 mvp',
        ),
        findsOneWidget,
      );
      expect(
        find.text('已启用本地 embedding 召回链路，可继续用于占位语义检索与索引构建。'),
        findsOneWidget,
      );
      expect(find.text('本地语义链路阶段概览'), findsOneWidget);
      expect(find.text('已完成 · 模型选择：已完成'), findsOneWidget);
      expect(find.text('已完成 · 检索范围：已启用本地语义检索'), findsOneWidget);
      expect(find.text('已完成 · 索引状态：可立即构建或刷新本地索引'), findsOneWidget);

      await reveal(tester, find.text('语义索引设置'));

      expect(find.text('语义索引设置'), findsOneWidget);
      expect(find.text('单 chunk 最大长度'), findsOneWidget);

      await reveal(tester, find.text('检索范围控制'));

      expect(find.text('检索范围控制'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows blocked state labels when semantic pipeline is incomplete',
    (tester) async {
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
          child: const MaterialApp(home: SearchSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('阻塞 · 模型选择：未完成'), findsOneWidget);
      expect(find.text('阻塞 · 检索范围：未启用本地语义检索'), findsOneWidget);
      expect(find.text('阻塞 · 索引状态：当前仍存在阻塞项'), findsOneWidget);
      expect(find.text('下一步可执行操作'), findsOneWidget);
      expect(find.text('前往模型管理选择语义模型'), findsOneWidget);
      expect(find.text('启用检索范围中的本地语义检索'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows aligned initial-index status and trigger action',
    (tester) async {
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'secret-1',
        sourceType: SearchSourceType.secret,
        title: '邮箱账号',
        updatedAt: DateTime(2026, 4, 21, 10, 0),
        plainTextHash: 'hash-align-1',
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
                ready: true,
                reason: '本地语义检索模型已就绪',
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

      expect(find.text('建议先构建本地索引'), findsOneWidget);
      expect(find.text('立即构建索引'), findsWidgets);
    },
  );

  testWidgets('SearchSettingsPage shows aligned refresh status and action', (
    tester,
  ) async {
    final pendingItem = SearchIndexPendingItem(
      sourceId: 'note-1',
      sourceType: SearchSourceType.note,
      title: '恢复码备忘',
      updatedAt: DateTime(2026, 4, 21, 11, 0),
      plainTextHash: 'hash-align-2',
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
              ready: true,
              reason: '本地语义检索模型已就绪',
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

    expect(find.text('索引需要刷新'), findsOneWidget);
    expect(find.text('刷新索引'), findsWidgets);
  });

  testWidgets(
    'SearchSettingsPage shows aligned failure status and retry action',
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

      expect(find.text('最近一次索引失败'), findsOneWidget);
      expect(find.text('重试索引'), findsOneWidget);
      expect(find.text('磁盘空间不足'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows aligned ready state without build prompt',
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

      expect(find.text('本地语义检索已可用'), findsOneWidget);
      expect(find.text('当前索引已最新，可以直接继续使用语义检索。'), findsOneWidget);
      expect(find.text('构建占位索引'), findsNothing);
    },
  );

  testWidgets(
    'SearchSettingsPage shows shared refresh hint and disables index actions while refresh session is active',
    (tester) async {
      final pendingItem = SearchIndexPendingItem(
        sourceId: 'secret-1',
        sourceType: SearchSourceType.secret,
        title: '邮箱账号',
        updatedAt: DateTime(2026, 4, 21, 10, 0),
        plainTextHash: 'hash-refresh-ui',
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
                ready: true,
                reason: '本地语义检索模型已就绪',
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
            searchRefreshSessionProvider.overrideWith(
              (ref) => const SearchRefreshSessionState(
                refreshing: true,
                message: '正在刷新搜索状态与结果...',
              ),
            ),
          ],
          child: const MaterialApp(home: SearchSettingsPage()),
        ),
      );

      await tester.pump();

      expect(find.text('正在刷新搜索状态与结果...'), findsWidgets);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '立即构建索引'),
      );
      expect(button.onPressed, isNull);
    },
  );
}
