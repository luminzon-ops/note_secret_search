part of 'search_settings_page_test.dart';

void _runSearchSettingsRefreshCases() {
  testWidgets(
    'SearchSettingsPage index action uses combined refresh controller flow',
    (tester) async {
      late _RecordingSearchRefreshRunner runner;
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

      await tester.pumpAndSettle();
      await revealAndTap(tester, find.widgetWithText(ActionChip, '立即构建索引'));
      await tester.pump();

      expect(runner.refreshCalls, 1);
    },
  );
}
