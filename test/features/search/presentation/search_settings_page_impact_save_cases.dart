part of 'search_settings_page_test.dart';

void _runSearchSettingsImpactSaveCases() {
  testWidgets(
    'SearchSettingsPage shows default impact guidance when there are no draft changes',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async =>
                  const SemanticSearchReadiness(ready: true, reason: 'ready'),
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
    },
  );

  testWidgets(
    'SearchSettingsPage shows immediate-impact guidance for scope draft changes',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async =>
                  const SemanticSearchReadiness(ready: true, reason: 'ready'),
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
      await tester.tap(find.widgetWithText(SwitchListTile, '密码字段'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('这些设置会如何影响结果'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('你当前的草稿会立即影响搜索结果。保存后可以直接回到搜索页查看变化。'), findsOneWidget);
      expect(find.text('• 密码字段检索范围'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows reindex guidance for index-content draft changes',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async =>
                  const SemanticSearchReadiness(ready: true, reason: 'ready'),
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
      await _selectChunkLength(tester, 160);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('这些设置会如何影响结果'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('你当前的草稿会影响语义索引内容。保存后需要重新索引，语义结果才会更新。'), findsOneWidget);
      expect(find.text('• 单 chunk 最大长度'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows mixed guidance and pending-item recommendation',
    (tester) async {
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
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async =>
                  const SemanticSearchReadiness(ready: true, reason: 'ready'),
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

      expect(
        find.text('你当前的草稿包含两类影响：部分改动会立即影响结果，部分改动需要重新索引后生效。'),
        findsOneWidget,
      );
      expect(find.text('当前已有待索引内容，建议保存后直接刷新索引。'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage shows post-save reindex action bar after saving index changes',
    (tester) async {
      final settingsUseCase = _RecordingSearchSettingsUseCase();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async =>
                  const SemanticSearchReadiness(ready: true, reason: 'ready'),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => const SearchIndexStatus(
                engineReady: true,
                engineReason: 'ready',
                hasActiveEmbeddingModel: true,
                pendingItems: <SearchIndexPendingItem>[],
              ),
            ),
            searchSettingsUseCaseProvider.overrideWith(
              (ref) => settingsUseCase,
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
      await _selectChunkLength(tester, 160);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存索引设置'));
      await tester.pumpAndSettle();

      expect(settingsUseCase.lastIndexSettings?.maxChunkLength, 160);
      expect(find.text('设置已保存，语义结果需要刷新索引后更新。'), findsOneWidget);
      expect(find.text('立即刷新'), findsOneWidget);
      expect(find.text('返回搜索'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage post-save reindex action bar triggers refresh flow',
    (tester) async {
      late _RecordingSearchRefreshRunner runner;
      final settingsUseCase = _RecordingSearchSettingsUseCase();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async =>
                  const SemanticSearchReadiness(ready: true, reason: 'ready'),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => const SearchIndexStatus(
                engineReady: true,
                engineReason: 'ready',
                hasActiveEmbeddingModel: true,
                pendingItems: <SearchIndexPendingItem>[],
              ),
            ),
            searchSettingsUseCaseProvider.overrideWith(
              (ref) => settingsUseCase,
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
      await tester.scrollUntilVisible(
        find.text('语义索引设置'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await _selectChunkLength(tester, 160);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存索引设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即刷新'));
      await tester.pump();

      expect(settingsUseCase.lastIndexSettings?.maxChunkLength, 160);
      expect(runner.refreshCalls, 1);
    },
  );

  testWidgets(
    'SearchSettingsPage post-save reindex action bar can return to search',
    (tester) async {
      final settingsUseCase = _RecordingSearchSettingsUseCase();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: AppDestination.search,
            builder: (context, state) =>
                const Scaffold(body: Text('search page')),
          ),
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
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async =>
                  const SemanticSearchReadiness(ready: true, reason: 'ready'),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => const SearchIndexStatus(
                engineReady: true,
                engineReason: 'ready',
                hasActiveEmbeddingModel: true,
                pendingItems: <SearchIndexPendingItem>[],
              ),
            ),
            searchSettingsUseCaseProvider.overrideWith(
              (ref) => settingsUseCase,
            ),
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
      await _selectChunkLength(tester, 160);
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

      expect(settingsUseCase.lastIndexSettings?.maxChunkLength, 160);
      expect(find.text('search page'), findsOneWidget);
    },
  );

  testWidgets(
    'SearchSettingsPage does not show post-save reindex action bar for immediate-only changes',
    (tester) async {
      final settingsUseCase = _RecordingSearchSettingsUseCase(
        scopeRequiresReindex: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchScopeConfigProvider.overrideWith(
              (ref) async => const SearchScopeConfig.defaults(),
            ),
            searchIndexSettingsProvider.overrideWith(
              (ref) async => const SearchIndexSettings.defaults(),
            ),
            semanticSearchReadinessProvider.overrideWith(
              (ref) async =>
                  const SemanticSearchReadiness(ready: true, reason: 'ready'),
            ),
            searchIndexStatusProvider.overrideWith(
              (ref) async => const SearchIndexStatus(
                engineReady: true,
                engineReason: 'ready',
                hasActiveEmbeddingModel: true,
                pendingItems: <SearchIndexPendingItem>[],
              ),
            ),
            searchSettingsUseCaseProvider.overrideWith(
              (ref) => settingsUseCase,
            ),
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
      await tester.tap(find.widgetWithText(SwitchListTile, '密码字段'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存检索范围'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存检索范围'));
      await tester.pumpAndSettle();

      expect(settingsUseCase.lastScope?.includePasswordField, isTrue);
      expect(find.text('设置已保存，语义结果需要刷新索引后更新。'), findsNothing);
      expect(find.text('立即刷新'), findsNothing);
      expect(find.text('返回搜索'), findsNothing);
    },
  );
}
