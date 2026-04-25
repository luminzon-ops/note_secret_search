import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/presentation/search_page.dart';
import 'package:note_secret_search/features/notes/presentation/note_detail_page.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_detail_page.dart';

class _FakeCryptoService implements CryptoService {
  const _FakeCryptoService();

  @override
  String decryptNullable(List<int>? ciphertext) {
    if (ciphertext == null) {
      return '';
    }
    return String.fromCharCodes(ciphertext);
  }

  @override
  List<int>? encryptNullable(String? plaintext) => plaintext?.codeUnits;
}

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

void main() {
  testWidgets('SearchPage shows settings entry and does not render inline settings cards', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        GoRoute(
          path: '/search/settings',
          builder: (context, state) => const Scaffold(body: Text('settings target')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
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
  });

  testWidgets('SearchPage empty feedback routes users to model management when runtime is unverified', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        GoRoute(path: '/models', builder: (context, state) => const Scaffold(body: Text('models target'))),
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
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
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
  });

  testWidgets('SearchPage shows blocked runtime action label for degraded readiness', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
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
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('本地语义链路未就绪'), findsOneWidget);
    expect(find.text('前往模型管理排查'), findsOneWidget);
  });

  testWidgets('SearchPage renders aggregated semantic explanation as separate readable lines', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account；账号：alice@example.com',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('• 标题：Bank Account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('语义命中'), findsWidgets);
    expect(find.text('• 标题：Bank Account'), findsOneWidget);
    expect(find.text('• 账号：alice@example.com'), findsOneWidget);
    expect(find.text('命中摘要：标题：Bank Account；账号：alice@example.com'), findsNothing);
  });

  testWidgets('SearchPage shows ranking reasons for strong keyword and semantic field matches', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account；账号：alice@example.com',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('排序依据'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('排序依据'), findsOneWidget);
    expect(find.text('• 强信号：同时命中关键词与语义检索'), findsOneWidget);
    expect(find.text('• 优先查看标题，这是当前最直接的命中位置。'), findsOneWidget);
  });

  testWidgets('SearchPage shows assist signal label for lower-priority semantic field reasons', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Finance Note',
                preview: 'banking tags',
                tags: const ['banking'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.72,
                semanticHitField: SemanticHitField.tags,
                semanticHitSummary: '标签：banking',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('• 中信号：命中语义检索'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('• 中信号：命中语义检索'), findsOneWidget);
    expect(find.text('• 优先查看标签字段，确认标签线索是否匹配。'), findsOneWidget);
  });

  testWidgets('SearchPage shows keyword-only retrieval summary when semantic search is not participating', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前检索链路'), findsOneWidget);
    expect(find.text('当前仅展示关键词检索结果，语义链路未参与此次结果排序。'), findsOneWidget);
    expect(find.text('结果构成：1 条关键词结果，0 条语义结果。'), findsOneWidget);
  });

  testWidgets('SearchPage shows mixed retrieval summary when semantic signals participate in unified results', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => [
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'secret-1',
                  type: SearchResultType.secret,
                  title: 'Bank Account',
                  preview: 'alice@example.com',
                  tags: const ['finance'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.96,
                hitSummary: '标题：Bank Account',
                hitField: SemanticHitField.title,
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前统一结果已混合关键词与语义信号，排序会优先展示双命中内容。'), findsOneWidget);
    expect(find.text('结果构成：1 条关键词结果，1 条语义结果。'), findsOneWidget);
    expect(find.text('下方“占位语义匹配”区块展示的是当前语义召回明细。'), findsOneWidget);
  });

  testWidgets('SearchPage shows semantic tier counts in the top summary when semantic signals are present', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
              SearchResultItem(
                id: 'secret-2',
                type: SearchResultType.secret,
                title: 'Vault Account',
                preview: 'vault@example.com',
                tags: const ['vault'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.91,
                semanticHitField: SemanticHitField.summary,
                semanticHitSummary: '摘要：Vault Account',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => [
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'secret-1',
                  type: SearchResultType.secret,
                  title: 'Bank Account',
                  preview: 'alice@example.com',
                  tags: const ['finance'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.96,
                hitSummary: '标题：Bank Account',
                hitField: SemanticHitField.title,
              ),
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'note-1',
                  type: SearchResultType.note,
                  title: 'Recovery Note',
                  preview: 'backup tags',
                  tags: const ['backup'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.72,
                hitSummary: '标签：backup',
                hitField: SemanticHitField.tags,
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('当前语义结果中，重点语义命中 2 条，补充语义线索 0 条。'), findsOneWidget);
  });

  testWidgets('SearchPage shows high-quality semantic explanation for title-based semantic hits', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('排序依据'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('• 重点语义命中：标题属于高可信语义字段'), findsOneWidget);
  });

  testWidgets('SearchPage shows assist semantic explanation for lower-priority semantic fields', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Finance Note',
                preview: 'banking tags',
                tags: const ['banking'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.72,
                semanticHitField: SemanticHitField.tags,
                semanticHitSummary: '标签：banking',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('排序依据'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('• 补充语义线索：标签属于补充语义线索'), findsOneWidget);
  });

  testWidgets('SearchPage does not show semantic tiering copy for keyword-only results', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('重点语义命中'), findsNothing);
    expect(find.textContaining('补充语义线索'), findsNothing);
  });

  testWidgets('SearchPage shows observability summary for mixed search result composition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Recovery Note',
                preview: 'backup tags',
                tags: const ['backup'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.72,
                semanticHitField: SemanticHitField.tags,
                semanticHitSummary: '标签：backup',
              ),
              SearchResultItem(
                id: 'note-2',
                type: SearchResultType.note,
                title: 'Codes Note',
                preview: 'body hit',
                tags: const ['codes'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.71,
                semanticHitField: SemanticHitField.noteBody,
                semanticHitSummary: '正文：codes',
              ),
              SearchResultItem(
                id: 'secret-2',
                type: SearchResultType.secret,
                title: 'Card PIN',
                preview: 'pin keyword only',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => [
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'secret-1',
                  type: SearchResultType.secret,
                  title: 'Bank Account',
                  preview: 'alice@example.com',
                  tags: const ['finance'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.96,
                hitSummary: '标题：Bank Account',
                hitField: SemanticHitField.title,
              ),
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'note-1',
                  type: SearchResultType.note,
                  title: 'Recovery Note',
                  preview: 'backup tags',
                  tags: const ['backup'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.72,
                hitSummary: '标签：backup',
                hitField: SemanticHitField.tags,
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '展开更多观测'));
    await tester.pumpAndSettle();

    expect(find.text('搜索观测摘要'), findsOneWidget);
    expect(find.text('命中结构：双命中 0 条，关键词优先 1 条，语义命中 2 条。'), findsOneWidget);
    expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsOneWidget);
    expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsOneWidget);
  });

  testWidgets('SearchPage shows semantic-only filtering stats in observability summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'dual',
                type: SearchResultType.secret,
                title: 'Dual Result',
                preview: 'dual preview',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Dual Result',
              ),
              SearchResultItem(
                id: 'kept-semantic',
                type: SearchResultType.note,
                title: 'Kept Semantic',
                preview: 'kept preview',
                tags: const ['backup'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.91,
                semanticHitField: SemanticHitField.summary,
                semanticHitSummary: '摘要：Kept Semantic',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => [
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'dual',
                  type: SearchResultType.secret,
                  title: 'Dual Result',
                  preview: 'dual preview',
                  tags: const ['finance'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.96,
                hitSummary: '标题：Dual Result',
                hitField: SemanticHitField.title,
              ),
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'kept-semantic',
                  type: SearchResultType.note,
                  title: 'Kept Semantic',
                  preview: 'kept preview',
                  tags: const ['backup'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.91,
                hitSummary: '摘要：Kept Semantic',
                hitField: SemanticHitField.summary,
              ),
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'filtered-semantic-1',
                  type: SearchResultType.note,
                  title: 'Filtered 1',
                  preview: 'filtered preview 1',
                  tags: const ['backup'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.72,
                hitSummary: '标签：backup',
                hitField: SemanticHitField.tags,
              ),
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'filtered-semantic-2',
                  type: SearchResultType.note,
                  title: 'Filtered 2',
                  preview: 'filtered preview 2',
                  tags: const ['codes'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.71,
                hitSummary: '正文：codes',
                hitField: SemanticHitField.noteBody,
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '展开更多观测'));
    await tester.pumpAndSettle();

    expect(find.text('语义过滤：语义直达候选 2 条，保留 1 条，过滤 1 条。'), findsOneWidget);
    expect(find.text('过滤原因：被过滤结果多数只提供补充语义线索，且未达到高分保留条件。'), findsOneWidget);
  });

  testWidgets('SearchPage hides observability field distribution when no semantic fields participate', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('搜索观测摘要'), findsOneWidget);
    expect(find.text('命中结构：双命中 0 条，关键词优先 1 条，语义命中 0 条。'), findsOneWidget);
    expect(find.textContaining('字段分布：'), findsNothing);
  });

  testWidgets('SearchPage shows dominant signal and dominant field hints in observability summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Recovery Note',
                preview: 'backup tags',
                tags: const ['backup'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.72,
                semanticHitField: SemanticHitField.tags,
                semanticHitSummary: '标签：backup',
              ),
              SearchResultItem(
                id: 'secret-2',
                type: SearchResultType.secret,
                title: 'Card PIN',
                preview: 'pin keyword only',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前结果主要由双命中主导（1 条）。'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '展开更多观测'));
    await tester.pumpAndSettle();

    expect(find.text('当前语义命中主要集中在标题字段（1 条）。'), findsOneWidget);
  });

  testWidgets('SearchPage shows reminder hint in observability summary when semantic participation is assist-field driven', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Recovery Note',
                preview: 'backup tags',
                tags: const ['backup'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.72,
                semanticHitField: SemanticHitField.tags,
                semanticHitSummary: '标签：backup',
              ),
              SearchResultItem(
                id: 'note-2',
                type: SearchResultType.note,
                title: 'Codes Note',
                preview: 'body hit',
                tags: const ['codes'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.71,
                semanticHitField: SemanticHitField.noteBody,
                semanticHitSummary: '正文：codes',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前语义参与主要来自辅助字段，建议谨慎判断结果质量。'), findsOneWidget);
  });

  testWidgets('SearchPage keeps observability summary compact by default', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Recovery Note',
                preview: 'backup tags',
                tags: const ['backup'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.72,
                semanticHitField: SemanticHitField.tags,
                semanticHitSummary: '标签：backup',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('命中结构：'), findsOneWidget);
    expect(find.text('展开更多观测'), findsOneWidget);

    expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsNothing);
    expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsNothing);
    expect(find.text('当前语义命中主要集中在正文字段（1 条）。'), findsNothing);
  });

  testWidgets('SearchPage can expand and collapse secondary observability diagnostics', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Recovery Note',
                preview: 'backup tags',
                tags: const ['backup'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.72,
                semanticHitField: SemanticHitField.tags,
                semanticHitSummary: '标签：backup',
              ),
              SearchResultItem(
                id: 'note-2',
                type: SearchResultType.note,
                title: 'Codes Note',
                preview: 'body hit',
                tags: const ['codes'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
                semanticScore: 0.71,
                semanticHitField: SemanticHitField.noteBody,
                semanticHitSummary: '正文：codes',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsNothing);
    expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsNothing);
    expect(find.text('当前语义命中主要集中在正文字段（1 条）。'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '展开更多观测'));
    await tester.pumpAndSettle();

    expect(find.text('收起观测详情'), findsOneWidget);
    expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsOneWidget);
    expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsOneWidget);
    expect(find.text('当前语义命中主要集中在正文字段（1 条）。'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '收起观测详情'));
    await tester.pumpAndSettle();

    expect(find.text('展开更多观测'), findsOneWidget);
    expect(find.text('语义分层：重点 0 条，补充线索 2 条。'), findsNothing);
    expect(find.text('字段分布：标签 1 条，正文 1 条。'), findsNothing);
    expect(find.text('当前语义命中主要集中在正文字段（1 条）。'), findsNothing);
  });

  testWidgets('SearchPage shows semantic quality gate hint when semantic signals participate in unified results', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => [
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'secret-1',
                  type: SearchResultType.secret,
                  title: 'Bank Account',
                  preview: 'alice@example.com',
                  tags: const ['finance'],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.96,
                hitSummary: '标题：Bank Account',
                hitField: SemanticHitField.title,
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前语义结果仅展示通过最低质量门槛的命中。'), findsOneWidget);
  });

  testWidgets('SearchPage shows empty-query guidance before the user starts searching', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('输入关键词、标签或语义描述后，这里会开始展示检索结果。'), findsOneWidget);
    expect(find.text('你也可以先前往“搜索设置与索引”调整检索范围或索引策略。'), findsOneWidget);
  });

  testWidgets('SearchPage shows no-result guidance when query has no matches and semantic search is not participating', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank account'),
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前查询暂无命中结果。'), findsOneWidget);
    expect(find.text('本次未找到匹配结果，建议检查检索范围、查询词，或刷新索引后再试。'), findsOneWidget);
    expect(find.text('前往搜索设置与索引'), findsOneWidget);
  });

  testWidgets('SearchPage no-result guidance action can navigate to search settings', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        GoRoute(
          path: '/search/settings',
          builder: (context, state) => const Scaffold(body: Text('settings target')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank account'),
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('前往搜索设置与索引'));
    await tester.pumpAndSettle();

    expect(find.text('settings target'), findsOneWidget);
  });

  testWidgets('SearchPage shows result overview and splits unified results into secret and note sections', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Recovery Note',
                preview: 'backup codes',
                tags: const ['backup'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('结果概览：共 2 条，密码 1 条，笔记 1 条。'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('结果概览：共 2 条，密码 1 条，笔记 1 条。'), findsOneWidget);
    expect(find.text('密码结果'), findsOneWidget);
    expect(find.text('笔记结果'), findsOneWidget);
    expect(find.text('Bank Account'), findsOneWidget);
    expect(find.text('Recovery Note'), findsOneWidget);
  });

  testWidgets('SearchPage shows result-card explanation for high-quality dual-hit result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('这条结果同时命中关键词与重点语义字段，可优先查看。'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('这条结果同时命中关键词与重点语义字段，可优先查看。'), findsOneWidget);
  });

  testWidgets('SearchPage shows aligned ready status when semantic pipeline is available', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        GoRoute(
          path: '/search/settings',
          builder: (context, state) => const Scaffold(body: Text('settings target')),
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
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('本地语义检索已可用'), findsOneWidget);
    expect(find.text('本地语义检索模型已就绪：MiniLM Embedding'), findsOneWidget);
    expect(find.text('前往搜索设置与索引'), findsNothing);
  });

  testWidgets('SearchPage shows aligned blocked semantic pipeline state with quick entry to model management', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        GoRoute(
          path: '/models',
          builder: (context, state) => const Scaffold(body: Text('models target')),
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
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
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
  });

  testWidgets('SearchPage shows aligned blocked status and model-management action', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        GoRoute(
          path: '/models',
          builder: (context, state) => const Scaffold(body: Text('models page')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: false, reason: '缺少可用 embedding 模型'),
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
  });

  testWidgets('SearchPage shows aligned initial-index status and action', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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

  testWidgets('SearchPage shows aligned refresh status and action', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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

  testWidgets('SearchPage shows aligned failure status and retry action', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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

  testWidgets('SearchPage shows aligned ready state without build prompts', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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

  testWidgets(
    'SearchPage shows refresh-in-progress hint and disables action while shared refresh session is active',
    (tester) async {
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            semanticSearchReadinessProvider.overrideWith(
              (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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
            unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
            semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pump();

      expect(find.text('正在刷新搜索状态与结果...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('SearchPage index action uses combined refresh controller flow', (tester) async {
    late _RecordingSearchIndexController controller;
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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
          searchIndexControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchIndexController(ref: ref);
            return controller;
          }),
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('立即构建索引'));
    await tester.pump();

    expect(controller.refreshCalls, 1);
  });

  testWidgets('SearchPage shows refresh completion feedback when query matches feedback context', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank'),
          searchRefreshFeedbackProvider.overrideWith(
            (ref) =>
                const SearchRefreshFeedbackState(
                  visible: true,
                  headline: '搜索状态已刷新',
                  message: '当前结果已更新，结果数量从 1 条变为 3 条。',
                  changed: true,
                  queryAtRefresh: 'bank',
                ),
          ),
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('搜索状态已刷新'), findsOneWidget);
    expect(find.text('当前结果已更新，结果数量从 1 条变为 3 条。'), findsOneWidget);
  });

  testWidgets('SearchPage shows pending-reindex handoff card when settings were saved without refreshing index', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
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
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('设置已保存，但语义结果还没刷新'), findsOneWidget);
    expect(find.text('你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。'), findsOneWidget);
    expect(find.text('立即刷新索引'), findsOneWidget);
  });

  testWidgets('SearchPage pending-reindex handoff action triggers refresh flow', (tester) async {
    late _RecordingSearchIndexController controller;
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
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
          searchIndexControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchIndexController(ref: ref);
            return controller;
          }),
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('立即刷新索引'));
    await tester.pump();

    expect(controller.refreshCalls, 1);
  });

  testWidgets('SearchPage clears pending-reindex handoff card after refresh starts successfully', (
    tester,
  ) async {
    late _RecordingSearchIndexController controller;
    final container = ProviderContainer(
      overrides: [
        searchPendingReindexHandoffProvider.overrideWith(
          (ref) => const SearchPendingReindexHandoffState(
            visible: true,
            message: '你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。',
          ),
        ),
        searchIndexControllerProvider.overrideWith((ref) {
          controller = _RecordingSearchIndexController(ref: ref);
          return controller;
        }),
        unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
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
    expect(container.read(searchPendingReindexHandoffProvider).visible, isFalse);
  });

  testWidgets('SearchPage keeps pending-reindex handoff card when refresh trigger fails', (
    tester,
  ) async {
    late _RecordingSearchIndexController controller;
    final container = ProviderContainer(
      overrides: [
        searchPendingReindexHandoffProvider.overrideWith(
          (ref) => const SearchPendingReindexHandoffState(
            visible: true,
            message: '你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。',
          ),
        ),
        searchIndexControllerProvider.overrideWith((ref) {
          controller = _RecordingSearchIndexController(ref: ref, error: StateError('refresh failed'));
          return controller;
        }),
        unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
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
    expect(container.read(searchPendingReindexHandoffProvider).visible, isTrue);
  });

  testWidgets('SearchPage does not show pending-reindex handoff card when no handoff state exists', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('设置已保存，但语义结果还没刷新'), findsNothing);
  });

  testWidgets('SearchPage shows dual-hit dominant overview summary', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'a',
                type: SearchResultType.secret,
                title: 'A',
                preview: 'a',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
              ),
              SearchResultItem(
                id: 'b',
                type: SearchResultType.secret,
                title: 'B',
                preview: 'b',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
              ),
              SearchResultItem(
                id: 'c',
                type: SearchResultType.note,
                title: 'C',
                preview: 'c',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前前排结果以双命中为主，关键词与语义信号共同参与排序。'), findsOneWidget);
    expect(find.text('前 3 条中：双命中 2 条，关键词优先 1 条，语义命中 0 条。'), findsOneWidget);
  });

  testWidgets('SearchPage shows keyword-dominant overview when semantic only assists', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'a',
                type: SearchResultType.secret,
                title: 'A',
                preview: 'a',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
              SearchResultItem(
                id: 'b',
                type: SearchResultType.secret,
                title: 'B',
                preview: 'b',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
              SearchResultItem(
                id: 'c',
                type: SearchResultType.note,
                title: 'C',
                preview: 'c',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => [
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'c',
                  type: SearchResultType.note,
                  title: 'C',
                  preview: 'c',
                  tags: const [],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.76,
                hitSummary: '标题：C',
                hitField: SemanticHitField.title,
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前前排结果以关键词命中为主，语义信号主要用于补充排序。'), findsOneWidget);
  });

  testWidgets('SearchPage shows semantic-dominant overview when semantic-assisted results lead', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'a',
                type: SearchResultType.secret,
                title: 'A',
                preview: 'a',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
              ),
              SearchResultItem(
                id: 'b',
                type: SearchResultType.note,
                title: 'B',
                preview: 'b',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => [
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'a',
                  type: SearchResultType.secret,
                  title: 'A',
                  preview: 'a',
                  tags: const [],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.88,
                hitSummary: '标题：A',
                hitField: SemanticHitField.title,
              ),
              SemanticSearchResult(
                item: SearchResultItem(
                  id: 'b',
                  type: SearchResultType.note,
                  title: 'B',
                  preview: 'b',
                  tags: const [],
                  favorite: false,
                  updatedAt: DateTime(2026, 1, 2),
                ),
                score: 0.81,
                hitSummary: '标题：B',
                hitField: SemanticHitField.title,
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前前排结果更多依赖语义召回，适合继续检查命中摘要与上下文。'), findsOneWidget);
  });

  testWidgets('SearchPage shows dual-hit chip on mixed-match results', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'a',
                type: SearchResultType.secret,
                title: 'A',
                preview: 'a',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('双命中'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('双命中'), findsOneWidget);
  });

  testWidgets('SearchPage shows keyword-primary and semantic-assist chips', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'bank'),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'a',
                type: SearchResultType.secret,
                title: 'A',
                preview: 'a',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
              SearchResultItem(
                id: 'b',
                type: SearchResultType.note,
                title: 'B',
                preview: 'b',
                tags: const [],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.semantic},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('关键词优先'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('关键词优先'), findsOneWidget);
    expect(find.text('语义命中'), findsOneWidget);
  });

  testWidgets('SearchPage hides refresh completion feedback when current query no longer matches', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => 'email'),
          searchRefreshFeedbackProvider.overrideWith(
            (ref) =>
                const SearchRefreshFeedbackState(
                  visible: true,
                  headline: '搜索状态已刷新',
                  message: '当前结果已更新，本轮刷新未改变当前结果。',
                  changed: false,
                  queryAtRefresh: 'bank',
                ),
          ),
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('搜索状态已刷新'), findsNothing);
    expect(find.text('当前结果已更新，本轮刷新未改变当前结果。'), findsNothing);
  });

  testWidgets('SearchPage passes search context into secret detail page', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        GoRoute(
          path: '/vault/secret/:id',
          builder: (context, state) => SecretDetailPage(
            secretId: state.pathParameters['id']!,
            searchQuery: state.uri.queryParameters['query'],
            searchSource: state.uri.queryParameters['source'],
            searchContext: state.uri.queryParameters['context'],
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          secretDetailProvider('secret-1').overrideWith(
            (ref) async => SecretItem(
              id: 'secret-1',
              vaultId: 'vault-1',
              title: 'Bank Account',
              usernameCiphertext: 'alice@example.com'.codeUnits,
              passwordCiphertext: 'secret-pass'.codeUnits,
              websiteUrlCiphertext: 'bank.example.com'.codeUnits,
              noteCiphertext: 'bank note'.codeUnits,
              tags: const ['finance'],
              categoryId: null,
              favorite: false,
              createdAt: DateTime(2026, 1, 2),
              updatedAt: DateTime(2026, 1, 2),
            ),
          ),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'secret-1',
                type: SearchResultType.secret,
                title: 'Bank Account',
                preview: 'alice@example.com',
                tags: const ['finance'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword, SearchMatchSource.semantic},
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('密码结果'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank Account').first);
    await tester.pumpAndSettle();

    expect(find.text('来自搜索'), findsOneWidget);
    expect(find.text('命中方式：双命中'), findsOneWidget);
    expect(find.text('查询词：Bank Account'), findsOneWidget);
    expect(find.text('命中说明：本次命中主要落在标题字段。'), findsOneWidget);
  });

  testWidgets('SearchPage passes search context into note detail page', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SearchPage()),
        GoRoute(
          path: '/notes/item/:id',
          builder: (context, state) => NoteDetailPage(
            noteId: state.pathParameters['id']!,
            searchQuery: state.uri.queryParameters['query'],
            searchSource: state.uri.queryParameters['source'],
            searchContext: state.uri.queryParameters['context'],
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoServiceProvider.overrideWith((ref) => const _FakeCryptoService()),
          noteDetailProvider('note-1').overrideWith(
            (ref) async => NoteItem(
              id: 'note-1',
              vaultId: 'vault-1',
              title: 'Recovery Note',
              contentCiphertext: 'backup codes'.codeUnits,
              summaryCacheCiphertext: 'summary'.codeUnits,
              tags: const ['backup'],
              categoryId: null,
              favorite: false,
              createdAt: DateTime(2026, 1, 2),
              updatedAt: DateTime(2026, 1, 2),
            ),
          ),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => [
              SearchResultItem(
                id: 'note-1',
                type: SearchResultType.note,
                title: 'Recovery Note',
                preview: 'backup codes',
                tags: const ['backup'],
                favorite: false,
                updatedAt: DateTime(2026, 1, 2),
                matchSources: const {SearchMatchSource.keyword},
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('笔记结果'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recovery Note').first);
    await tester.pumpAndSettle();

    expect(find.text('来自搜索'), findsOneWidget);
    expect(find.text('命中方式：关键词优先'), findsOneWidget);
    expect(find.text('查询词：Recovery Note'), findsOneWidget);
  });

  testWidgets('SearchPage shows index build recommendation when pending items exist before any completed run', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('待索引内容：1 项'), findsOneWidget);
    expect(find.text('建议先构建本地索引'), findsOneWidget);
    expect(find.text('已有待索引内容，完成首次构建后再查看语义检索结果会更稳定。'), findsOneWidget);
    expect(find.text('立即构建索引'), findsOneWidget);
  });

  testWidgets('SearchPage shows index refresh recommendation when new pending items exist after a completed run', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('待索引内容：1 项'), findsOneWidget);
    expect(find.text('索引需要刷新'), findsOneWidget);
    expect(find.text('索引已有新变更，建议刷新后再判断当前语义检索结果。'), findsOneWidget);
    expect(find.text('刷新索引'), findsOneWidget);
  });

  testWidgets('SearchPage can trigger combined refresh action and show success feedback', (tester) async {
    late _RecordingSearchIndexController controller;
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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
          searchIndexControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchIndexController(ref: ref);
            return controller;
          }),
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('立即构建索引'));
    await tester.pump();

    expect(controller.refreshCalls, 1);
    expect(find.text('已开始构建索引，请稍后刷新搜索结果。'), findsOneWidget);
  });

  testWidgets('SearchPage shows failure feedback when combined refresh action fails', (tester) async {
    late _RecordingSearchIndexController controller;
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
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
          searchIndexControllerProvider.overrideWith((ref) {
            controller = _RecordingSearchIndexController(ref: ref, error: StateError('索引失败'));
            return controller;
          }),
          unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
          semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新索引'));
    await tester.pump();

    expect(controller.refreshCalls, 1);
    expect(find.text('索引触发失败，请稍后重试。'), findsOneWidget);
  });
}
