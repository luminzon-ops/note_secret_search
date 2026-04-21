import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/presentation/search_page.dart';

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

    expect(find.text('语义命中'), findsOneWidget);
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

    expect(find.text('排序依据'), findsOneWidget);
    expect(find.text('• 强信号：同时命中关键词与语义检索'), findsOneWidget);
    expect(find.text('• 强信号：标题属于高优先级语义命中'), findsOneWidget);
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

    expect(find.text('• 中信号：命中语义检索'), findsOneWidget);
    expect(find.text('• 辅助信号：标签提供辅助语义命中'), findsOneWidget);
  });
}
