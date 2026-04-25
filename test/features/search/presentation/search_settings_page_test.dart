import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/presentation/search_settings_page.dart';

class _RecordingSearchIndexController extends SearchIndexController {
  _RecordingSearchIndexController({required super.ref, this.error});

  int calls = 0;
  int refreshCalls = 0;
  final Object? error;

  @override
  Future<void> indexPending() async {
    calls++;
    if (error != null) {
      throw error!;
    }
  }

  @override
  Future<void> indexPendingAndRefresh() async {
    refreshCalls++;
    if (error != null) {
      throw error!;
    }
  }
}

class _RecordingSearchIndexSettingsController extends SearchIndexSettingsController {
  _RecordingSearchIndexSettingsController({required super.ref});

  SearchIndexSettings? lastSaved;

  @override
  Future<void> update(SearchIndexSettings settings) async {
    lastSaved = settings;
  }
}

class _RecordingSearchScopeController extends SearchScopeController {
  _RecordingSearchScopeController({required super.ref});

  SearchScopeConfig? lastSaved;

  @override
  Future<void> update(SearchScopeConfig config) async {
    lastSaved = config;
  }
}

void main() {
  testWidgets('SearchSettingsPage shows search scope, semantic status, and index settings sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
      find.text('builtin · embedding · Q8 · 版本 1.0 · 0.0 MB · RAM ≥ 512MB · 推荐档位 mvp'),
      findsOneWidget,
    );
    expect(find.text('已启用本地 embedding 召回链路，可继续用于占位语义检索与索引构建。'), findsOneWidget);
    expect(find.text('本地语义链路阶段概览'), findsOneWidget);
    expect(find.text('已完成 · 模型选择：已完成'), findsOneWidget);
    expect(find.text('已完成 · 检索范围：已启用本地语义检索'), findsOneWidget);
    expect(find.text('已完成 · 索引状态：可立即构建或刷新本地索引'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('语义索引设置'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('语义索引设置'), findsOneWidget);
    expect(find.text('单 chunk 最大长度'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('检索范围控制'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('检索范围控制'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows blocked state labels when semantic pipeline is incomplete', (
    tester,
  ) async {
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
  });

  testWidgets('SearchSettingsPage shows aligned initial-index status and trigger action', (tester) async {
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('建议先构建本地索引'), findsOneWidget);
    expect(find.text('立即构建索引'), findsWidgets);
  });

  testWidgets('SearchSettingsPage shows aligned refresh status and action', (tester) async {
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('索引需要刷新'), findsOneWidget);
    expect(find.text('刷新索引'), findsWidgets);
  });

  testWidgets('SearchSettingsPage shows aligned failure status and retry action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('最近一次索引失败'), findsOneWidget);
    expect(find.text('重试索引'), findsOneWidget);
    expect(find.text('磁盘空间不足'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows aligned ready state without build prompt', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('本地语义检索已可用'), findsOneWidget);
    expect(find.text('当前索引已最新，可以直接继续使用语义检索。'), findsOneWidget);
    expect(find.text('构建占位索引'), findsNothing);
  });

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
            searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
            searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
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
      final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('SearchSettingsPage index action uses combined refresh controller flow', (tester) async {
    late _RecordingSearchIndexController controller;
    final pendingItem = SearchIndexPendingItem(
      sourceId: 'secret-1',
      sourceType: SearchSourceType.secret,
      title: '邮箱账号',
      updatedAt: DateTime(2026, 4, 21, 10, 0),
      plainTextHash: 'hash-refresh-controller',
      indexPlainText: '邮箱账号\nuser@example.com',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          searchIndexControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchIndexController(ref: ref);
            return controller;
          }),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('立即构建索引').first);
    await tester.pump();

    expect(controller.refreshCalls, 1);
  });

  testWidgets('SearchSettingsPage shows default impact guidance when there are no draft changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready'),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => const SearchIndexStatus(
              engineReady: true,
              engineReason: 'ready',
              hasActiveEmbeddingModel: true,
              pendingItems: <SearchIndexPendingItem>[],
            ),
          ),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这些设置会如何影响结果'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('这些设置会如何影响结果'), findsOneWidget);
    expect(find.text('检索范围类设置会立即影响结果；索引内容类设置在你下次重建索引后生效。'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows immediate-impact guidance for scope draft changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready'),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => const SearchIndexStatus(
              engineReady: true,
              engineReason: 'ready',
              hasActiveEmbeddingModel: true,
              pendingItems: <SearchIndexPendingItem>[],
            ),
          ),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这些设置会如何影响结果'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('检索范围控制'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '检索标题'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这些设置会如何影响结果'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('你当前的草稿会立即影响搜索结果。保存后可以直接回到搜索页查看变化。'), findsOneWidget);
    expect(find.text('• 标题检索范围'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows reindex guidance for index-content draft changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready'),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => const SearchIndexStatus(
              engineReady: true,
              engineReason: 'ready',
              hasActiveEmbeddingModel: true,
              pendingItems: <SearchIndexPendingItem>[],
            ),
          ),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('语义索引设置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '索引密码附注'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这些设置会如何影响结果'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('你当前的草稿会影响语义索引内容。保存后需要重新索引，语义结果才会更新。'), findsOneWidget);
    expect(find.text('• 索引密码附注'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows mixed guidance and pending-item recommendation', (
    tester,
  ) async {
    final pendingItem = SearchIndexPendingItem(
      sourceId: 'secret-1',
      sourceType: SearchSourceType.secret,
      title: 'Bank Account',
      updatedAt: DateTime(2026, 4, 22, 10, 0),
      plainTextHash: 'hash-1',
      indexPlainText: 'Bank Account',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready'),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => SearchIndexStatus(
              engineReady: true,
              engineReason: 'ready',
              hasActiveEmbeddingModel: true,
              pendingItems: [pendingItem],
            ),
          ),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('语义索引设置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '索引密码附注'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这些设置会如何影响结果'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('检索范围控制'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '检索标题'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这些设置会如何影响结果'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('你当前的草稿包含两类影响：部分改动会立即影响结果，部分改动需要重新索引后生效。'), findsOneWidget);
    expect(find.text('当前已有待索引内容，建议保存后直接刷新索引。'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows post-save reindex action bar after saving index changes', (
    tester,
  ) async {
    late _RecordingSearchIndexSettingsController settingsController;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready'),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => const SearchIndexStatus(
              engineReady: true,
              engineReason: 'ready',
              hasActiveEmbeddingModel: true,
              pendingItems: <SearchIndexPendingItem>[],
            ),
          ),
          searchIndexSettingsControllerProvider.overrideWith((ref) {
            settingsController = _RecordingSearchIndexSettingsController(ref: ref);
            return settingsController;
          }),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('语义索引设置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '索引密码附注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存索引设置'));
    await tester.pumpAndSettle();

    expect(settingsController.lastSaved?.includeSecretNotes, isFalse);
    expect(find.text('设置已保存，语义结果需要刷新索引后更新。'), findsOneWidget);
    expect(find.text('立即刷新'), findsOneWidget);
    expect(find.text('返回搜索'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage post-save reindex action bar triggers refresh flow', (
    tester,
  ) async {
    late _RecordingSearchIndexController indexController;
    late _RecordingSearchIndexSettingsController settingsController;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready'),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => const SearchIndexStatus(
              engineReady: true,
              engineReason: 'ready',
              hasActiveEmbeddingModel: true,
              pendingItems: <SearchIndexPendingItem>[],
            ),
          ),
          searchIndexSettingsControllerProvider.overrideWith((ref) {
            settingsController = _RecordingSearchIndexSettingsController(ref: ref);
            return settingsController;
          }),
          searchIndexControllerProvider.overrideWith((ref) {
            indexController = _RecordingSearchIndexController(ref: ref);
            return indexController;
          }),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('语义索引设置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '索引密码附注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存索引设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即刷新'));
    await tester.pump();

    expect(settingsController.lastSaved?.includeSecretNotes, isFalse);
    expect(indexController.refreshCalls, 1);
  });

  testWidgets('SearchSettingsPage post-save reindex action bar can return to search', (tester) async {
    late _RecordingSearchIndexSettingsController settingsController;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('search page'))),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SearchSettingsPage(),
        ),
      ],
      initialLocation: '/settings',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready'),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => const SearchIndexStatus(
              engineReady: true,
              engineReason: 'ready',
              hasActiveEmbeddingModel: true,
              pendingItems: <SearchIndexPendingItem>[],
            ),
          ),
          searchIndexSettingsControllerProvider.overrideWith((ref) {
            settingsController = _RecordingSearchIndexSettingsController(ref: ref);
            return settingsController;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('语义索引设置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '索引密码附注'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存索引设置'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存索引设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回搜索'));
    await tester.pumpAndSettle();

    expect(settingsController.lastSaved?.includeSecretNotes, isFalse);
    expect(find.text('search page'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage does not show post-save reindex action bar for immediate-only changes', (
    tester,
  ) async {
    late _RecordingSearchScopeController scopeController;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready'),
          ),
          searchIndexStatusProvider.overrideWith(
            (ref) async => const SearchIndexStatus(
              engineReady: true,
              engineReason: 'ready',
              hasActiveEmbeddingModel: true,
              pendingItems: <SearchIndexPendingItem>[],
            ),
          ),
          searchScopeControllerProvider.overrideWith((ref) {
            scopeController = _RecordingSearchScopeController(ref: ref);
            return scopeController;
          }),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('检索范围控制'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '检索标题'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存检索范围'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存检索范围'));
    await tester.pumpAndSettle();

    expect(scopeController.lastSaved?.includeTitle, isFalse);
    expect(find.text('设置已保存，语义结果需要刷新索引后更新。'), findsNothing);
    expect(find.text('立即刷新'), findsNothing);
    expect(find.text('返回搜索'), findsNothing);
  });

  testWidgets('SearchSettingsPage blocked guidance can navigate to model management', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchSettingsPage()),
        GoRoute(
          path: '/models',
          builder: (context, state) => const Scaffold(body: Text('models page')),
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
  });

  testWidgets('SearchSettingsPage shows build-index guidance when pending items are actionable', (
    tester,
  ) async {
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage shows mixed pending item summary for secrets and notes', (
    tester,
  ) async {
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage shows refresh-index guidance after a prior completed index run', (
    tester,
  ) async {
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage explains that index is up to date after a successful run with no pending items', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
    expect(find.text('当前索引已最新，可以直接继续检索。'), findsWidgets);
    expect(find.text('待索引摘要：暂无待处理项'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage explains that index refresh is needed when new pending items exist after a successful run', (
    tester,
  ) async {
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage explains latest indexing failure when last run errored', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage explains first-time index build when pending items exist but no run has completed', (
    tester,
  ) async {
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage shows running-state summary while indexing is in progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage shows latest run summary when a prior indexing run completed', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage does not show index guidance when indexing is not actionable', (
    tester,
  ) async {
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });

  testWidgets('SearchSettingsPage shows detailed active model summary when capability metadata exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: '本地语义检索可用',
              activeEmbeddingModel: ModelRegistryEntry(
                id: 'embed-1',
                type: 'embedding',
                provider: 'builtin',
                name: 'MiniLM Embedding',
                version: '1.0.2',
                sizeBytes: 10485760,
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

    expect(find.textContaining('builtin · embedding · Q8'), findsOneWidget);
    expect(find.textContaining('版本 1.0.2'), findsOneWidget);
    expect(find.textContaining('10.0 MB'), findsOneWidget);
    expect(find.textContaining('RAM ≥ 512MB'), findsOneWidget);
    expect(find.textContaining('推荐档位 mvp'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage omits absent model metadata from the active model summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: '本地语义检索可用',
              activeEmbeddingModel: ModelRegistryEntry(
                id: 'embed-1',
                type: 'embedding',
                provider: 'builtin',
                name: 'MiniLM Embedding',
                version: null,
                sizeBytes: null,
                quantization: null,
                minRamMb: null,
                recommendedTier: null,
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

    expect(find.text('builtin · embedding'), findsOneWidget);
    expect(find.textContaining('版本'), findsNothing);
    expect(find.textContaining('RAM ≥'), findsNothing);
    expect(find.textContaining('推荐档位'), findsNothing);
  });

  testWidgets('SearchSettingsPage shows ready deployment status for an installed active model', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: '本地语义检索可用',
              activeEmbeddingModel: ModelRegistryEntry(
                id: 'embed-1',
                type: 'embedding',
                provider: 'builtin',
                name: 'MiniLM Embedding',
                version: '1.0.2',
                sizeBytes: 10485760,
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

    expect(find.text('部署状态：本地文件已就绪，可用于当前语义检索。'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows degraded deployment status when the active model file is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: '本地语义检索可用',
              activeEmbeddingModel: ModelRegistryEntry(
                id: 'embed-1',
                type: 'embedding',
                provider: 'builtin',
                name: 'MiniLM Embedding',
                version: '1.0.2',
                sizeBytes: 10485760,
                quantization: 'Q8',
                minRamMb: 512,
                recommendedTier: 'mvp',
                localPath: '/data/models/minilm.onnx',
                checksum: 'abc',
                enabled: true,
                installedAt: null,
                filePresent: false,
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

    expect(find.text('部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage index guidance triggers pending indexing', (tester) async {
    late _RecordingSearchIndexController controller;
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
          searchIndexControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchIndexController(ref: ref);
            return controller;
          }),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('立即构建索引').first);
    await tester.pump();

    expect(controller.refreshCalls, 1);
  });

  testWidgets('SearchSettingsPage shows success feedback after triggering index build', (tester) async {
    late _RecordingSearchIndexController controller;
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
          searchIndexControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchIndexController(ref: ref);
            return controller;
          }),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('立即构建索引').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即构建索引').first);
    await tester.pump();

    expect(controller.refreshCalls, 1);
    expect(find.text('已开始处理待索引内容，请稍后查看最新结果。'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows failure feedback after triggering index build', (tester) async {
    late _RecordingSearchIndexController controller;
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
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
          searchIndexControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchIndexController(ref: ref, error: StateError('索引失败'));
            return controller;
          }),
        ],
        child: const MaterialApp(home: SearchSettingsPage()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('立即构建索引').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即构建索引').first);
    await tester.pump();

    expect(controller.refreshCalls, 1);
    expect(find.text('索引触发失败，请稍后重试。'), findsOneWidget);
  });

  testWidgets('SearchSettingsPage shows no-pending feedback when index can run but nothing needs processing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
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
  });
}
