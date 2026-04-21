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
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/presentation/search_settings_page.dart';

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
    expect(find.text('本地语义检索已就绪'), findsOneWidget);
    expect(find.text('当前语义能力'), findsOneWidget);
    expect(find.text('MiniLM Embedding'), findsOneWidget);
    expect(find.text('builtin · embedding · Q8'), findsOneWidget);
    expect(find.text('已启用本地 embedding 召回链路，可继续用于占位语义检索与索引构建。'), findsOneWidget);
    expect(find.text('本地语义链路阶段'), findsOneWidget);
    expect(find.text('已完成 · 模型选择：已完成'), findsOneWidget);
    expect(find.text('已完成 · 检索范围：已启用本地语义检索'), findsOneWidget);
    expect(find.text('已完成 · 索引状态：可立即构建或刷新本地索引'), findsOneWidget);
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
    expect(find.text('下一步建议'), findsOneWidget);
    expect(find.text('前往模型管理'), findsOneWidget);
    expect(find.text('启用本地语义检索'), findsOneWidget);
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

    await tester.tap(find.text('前往模型管理'));
    await tester.pumpAndSettle();

    expect(find.text('models page'), findsOneWidget);
  });
}
