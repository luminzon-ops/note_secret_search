part of 'search_page_test.dart';

void _registerSearchPageNavigationCases() {
  testWidgets('SearchPage passes search context into secret detail page', (
    tester,
  ) async {
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
          cryptoServiceProvider.overrideWith(
            (ref) => const _FakeCryptoService(),
          ),
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
                matchSources: const {
                  SearchMatchSource.keyword,
                  SearchMatchSource.semantic,
                },
                semanticScore: 0.96,
                semanticHitField: SemanticHitField.title,
                semanticHitSummary: '标题：Bank Account',
              ),
            ],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await _revealSearchPage(tester, find.text('密码结果'));
    await tester.tap(find.text('Bank Account').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('来自搜索'), findsOneWidget);
    expect(find.text('命中方式：双命中'), findsOneWidget);
    expect(find.text('查询词：Bank Account'), findsOneWidget);
    expect(find.text('命中说明：本次命中主要落在标题字段。'), findsOneWidget);
  });

  testWidgets('SearchPage passes search context into note detail page', (
    tester,
  ) async {
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
          cryptoServiceProvider.overrideWith(
            (ref) => const _FakeCryptoService(),
          ),
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
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await _revealSearchPage(tester, find.text('笔记结果'));
    await tester.tap(find.text('Recovery Note').hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('来自搜索'), findsOneWidget);
    expect(find.text('命中方式：关键词优先'), findsOneWidget);
    expect(find.text('查询词：Recovery Note'), findsOneWidget);
  });
}
