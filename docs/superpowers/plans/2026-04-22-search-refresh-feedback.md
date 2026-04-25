# Search Refresh Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在索引并自动刷新完成后，为用户提供可解释的刷新完成反馈，明确说明搜索状态已刷新、当前结果已更新，以及本轮刷新是否影响当前结果。

**Architecture:** 在现有 `searchRefreshSessionProvider` 之外新增一个轻量的刷新完成反馈状态 provider，由 `SearchIndexController.indexPendingAndRefresh()` 在刷新前后采样 unified results 并生成摘要。`SearchPage` 负责渲染这条完成反馈，并在 query 改变时隐藏旧反馈，`SearchSettingsPage` 保持现状不扩张职责。

**Tech Stack:** Flutter, Riverpod, flutter_test

---

## File Structure

- Modify: `lib/features/search/application/search_providers.dart`
  - 新增刷新完成反馈状态模型与 provider
  - 在 `indexPendingAndRefresh()` 中补齐刷新前后结果采样、变化判断与反馈生成
- Modify: `lib/features/search/presentation/search_page.dart`
  - 渲染刷新完成反馈卡片
  - 基于当前 query 与 `queryAtRefresh` 控制显示/隐藏
- Modify: `test/features/search/presentation/search_page_test.dart`
  - 为刷新完成反馈新增 UI 测试
- Create or Modify: `test/features/search/application/search_providers_test.dart`
  - 为刷新反馈状态生成逻辑补齐应用层测试

### Task 1: 应用层刷新完成反馈状态

**Files:**
- Modify: `lib/features/search/application/search_providers.dart`
- Test: `test/features/search/application/search_providers_test.dart`

- [ ] **Step 1: Write the failing test for empty-query feedback**

```dart
test('indexPendingAndRefresh writes empty-query feedback after refresh completes', () async {
  final container = ProviderContainer(
    overrides: [
      searchQueryProvider.overrideWith((ref) => StateController('')),
      searchIndexStatusProvider.overrideWith(
        (ref) async => const SearchIndexStatus(
          engineReady: true,
          engineReason: 'ready',
          hasActiveEmbeddingModel: true,
          pendingItems: <SearchIndexPendingItem>[],
        ),
      ),
      activeEmbeddingModelProvider.overrideWith((ref) async => _fakeEmbeddingModel),
      searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
      searchIndexServiceProvider.overrideWith((ref) => _NoopSearchIndexService()),
      unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
      semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
    ],
  );

  addTearDown(container.dispose);

  await container.read(searchIndexControllerProvider).indexPendingAndRefresh();

  final feedback = container.read(searchRefreshFeedbackProvider);
  expect(feedback.visible, isTrue);
  expect(feedback.headline, '搜索状态已刷新');
  expect(feedback.message, '输入关键词后可查看最新结果。');
  expect(feedback.changed, isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/application/search_providers_test.dart --plain-name "indexPendingAndRefresh writes empty-query feedback after refresh completes"`

Expected: FAIL because `searchRefreshFeedbackProvider` / feedback fields do not exist yet.

- [ ] **Step 3: Write the failing test for unchanged results feedback**

```dart
test('indexPendingAndRefresh writes unchanged feedback when unified result ids stay the same', () async {
  final container = ProviderContainer(
    overrides: [
      searchQueryProvider.overrideWith((ref) => StateController('bank')),
      unifiedSearchResultsProvider.overrideWith((ref) async => _results(['a', 'b'])),
      semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      searchIndexStatusProvider.overrideWith((ref) async => _readyStatus()),
      activeEmbeddingModelProvider.overrideWith((ref) async => _fakeEmbeddingModel),
      searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
      searchIndexServiceProvider.overrideWith((ref) => _NoopSearchIndexService()),
    ],
  );

  addTearDown(container.dispose);

  await container.read(searchIndexControllerProvider).indexPendingAndRefresh();

  final feedback = container.read(searchRefreshFeedbackProvider);
  expect(feedback.visible, isTrue);
  expect(feedback.changed, isFalse);
  expect(feedback.message, '当前结果已更新，本轮刷新未改变当前结果。');
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/features/search/application/search_providers_test.dart --plain-name "indexPendingAndRefresh writes unchanged feedback when unified result ids stay the same"`

Expected: FAIL because feedback generation logic does not exist yet.

- [ ] **Step 5: Write the failing test for changed count feedback**

```dart
test('indexPendingAndRefresh writes changed-count feedback when result count changes', () async {
  final results = <List<SearchResultItem>>[
    _results(['a']),
    _results(['a', 'b', 'c']),
  ];

  final container = ProviderContainer(
    overrides: [
      searchQueryProvider.overrideWith((ref) => StateController('bank')),
      unifiedSearchResultsProvider.overrideWith((ref) async => results.removeAt(0)),
      semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      searchIndexStatusProvider.overrideWith((ref) async => _readyStatus()),
      activeEmbeddingModelProvider.overrideWith((ref) async => _fakeEmbeddingModel),
      searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
      searchIndexServiceProvider.overrideWith((ref) => _NoopSearchIndexService()),
    ],
  );

  addTearDown(container.dispose);

  await container.read(searchIndexControllerProvider).indexPendingAndRefresh();

  final feedback = container.read(searchRefreshFeedbackProvider);
  expect(feedback.visible, isTrue);
  expect(feedback.changed, isTrue);
  expect(feedback.message, '当前结果已更新，结果数量从 1 条变为 3 条。');
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/features/search/application/search_providers_test.dart --plain-name "indexPendingAndRefresh writes changed-count feedback when result count changes"`

Expected: FAIL because before/after result comparison is not implemented.

- [ ] **Step 7: Write the failing test for changed-order feedback**

```dart
test('indexPendingAndRefresh writes reorder feedback when ids change order with same count', () async {
  final results = <List<SearchResultItem>>[
    _results(['a', 'b']),
    _results(['b', 'a']),
  ];

  final container = ProviderContainer(
    overrides: [
      searchQueryProvider.overrideWith((ref) => StateController('bank')),
      unifiedSearchResultsProvider.overrideWith((ref) async => results.removeAt(0)),
      semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      searchIndexStatusProvider.overrideWith((ref) async => _readyStatus()),
      activeEmbeddingModelProvider.overrideWith((ref) async => _fakeEmbeddingModel),
      searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
      searchIndexServiceProvider.overrideWith((ref) => _NoopSearchIndexService()),
    ],
  );

  addTearDown(container.dispose);

  await container.read(searchIndexControllerProvider).indexPendingAndRefresh();

  final feedback = container.read(searchRefreshFeedbackProvider);
  expect(feedback.visible, isTrue);
  expect(feedback.changed, isTrue);
  expect(feedback.message, '当前结果已更新，本轮刷新调整了结果排序。');
});
```

- [ ] **Step 8: Run test to verify it fails**

Run: `flutter test test/features/search/application/search_providers_test.dart --plain-name "indexPendingAndRefresh writes reorder feedback when ids change order with same count"`

Expected: FAIL because reorder-specific feedback is not implemented.

- [ ] **Step 9: Write minimal implementation for feedback state and controller logic**

```dart
final searchRefreshFeedbackProvider = StateProvider<SearchRefreshFeedbackState>(
  (ref) => const SearchRefreshFeedbackState.hidden(),
);

class SearchRefreshFeedbackState {
  const SearchRefreshFeedbackState({
    required this.visible,
    this.headline,
    this.message,
    this.changed,
    this.queryAtRefresh,
    this.completedAt,
  });

  const SearchRefreshFeedbackState.hidden()
      : visible = false,
        headline = null,
        message = null,
        changed = null,
        queryAtRefresh = null,
        completedAt = null;

  final bool visible;
  final String? headline;
  final String? message;
  final bool? changed;
  final String? queryAtRefresh;
  final DateTime? completedAt;
}
```

```dart
Future<void> indexPendingAndRefresh() async {
  final query = _ref.read(searchQueryProvider).trim();
  final beforeResults = await _ref.read(unifiedSearchResultsProvider.future);
  final beforeIds = beforeResults.map((item) => item.id).toList(growable: false);

  _ref.read(searchRefreshFeedbackProvider.notifier).state =
      const SearchRefreshFeedbackState.hidden();

  await indexPending();

  _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle()
      .copyWith(refreshing: true, message: '正在刷新搜索状态与结果...');

  try {
    _ref.invalidate(searchIndexStatusProvider);
    _ref.invalidate(semanticSearchResultsProvider);
    _ref.invalidate(unifiedSearchResultsProvider);

    await _ref.read(searchIndexStatusProvider.future);
    await _ref.read(semanticSearchResultsProvider.future);
    final afterResults = await _ref.read(unifiedSearchResultsProvider.future);
    final afterIds = afterResults.map((item) => item.id).toList(growable: false);

    _ref.read(searchRefreshFeedbackProvider.notifier).state = _buildRefreshFeedback(
      query: query,
      beforeIds: beforeIds,
      afterIds: afterIds,
    );

    _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle()
        .copyWith(lastCompletedAt: DateTime.now());
  } catch (_) {
    _ref.read(searchRefreshFeedbackProvider.notifier).state =
        const SearchRefreshFeedbackState.hidden();
    _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle();
    rethrow;
  }
}
```

- [ ] **Step 10: Run targeted tests to verify they pass**

Run: `flutter test test/features/search/application/search_providers_test.dart`

Expected: PASS

### Task 2: SearchPage 完成反馈卡片

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing widget test for visible refresh feedback**

```dart
testWidgets('SearchPage shows refresh completion feedback when query matches feedback context', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchQueryProvider.overrideWith((ref) => StateController('bank')),
        searchRefreshFeedbackProvider.overrideWith(
          (ref) => StateController(
            SearchRefreshFeedbackState(
              visible: true,
              headline: '搜索状态已刷新',
              message: '当前结果已更新，结果数量从 1 条变为 3 条。',
              changed: true,
              queryAtRefresh: 'bank',
              completedAt: DateTime(2026, 4, 22, 12, 0),
            ),
          ),
        ),
        unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
      child: MaterialApp(home: SearchPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('搜索状态已刷新'), findsOneWidget);
  expect(find.text('当前结果已更新，结果数量从 1 条变为 3 条。'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows refresh completion feedback when query matches feedback context"`

Expected: FAIL because completion feedback card is not rendered yet.

- [ ] **Step 3: Write the failing widget test for hiding stale feedback after query changes**

```dart
testWidgets('SearchPage hides refresh completion feedback when current query no longer matches', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchQueryProvider.overrideWith((ref) => StateController('email')),
        searchRefreshFeedbackProvider.overrideWith(
          (ref) => StateController(
            SearchRefreshFeedbackState(
              visible: true,
              headline: '搜索状态已刷新',
              message: '当前结果已更新，本轮刷新未改变当前结果。',
              changed: false,
              queryAtRefresh: 'bank',
              completedAt: DateTime(2026, 4, 22, 12, 0),
            ),
          ),
        ),
        unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
      child: MaterialApp(home: SearchPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('搜索状态已刷新'), findsNothing);
  expect(find.text('当前结果已更新，本轮刷新未改变当前结果。'), findsNothing);
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage hides refresh completion feedback when current query no longer matches"`

Expected: FAIL because stale feedback hiding is not implemented yet.

- [ ] **Step 5: Write minimal implementation for the completion feedback card**

```dart
final refreshFeedback = ref.watch(searchRefreshFeedbackProvider);

if (_shouldShowRefreshFeedback(query: query, feedback: refreshFeedback, refreshing: refreshSession.refreshing))
  _SearchRefreshFeedbackCard(feedback: refreshFeedback)
else
  const SizedBox.shrink()
```

```dart
class _SearchRefreshFeedbackCard extends StatelessWidget {
  const _SearchRefreshFeedbackCard({required this.feedback});

  final SearchRefreshFeedbackState feedback;

  @override
  Widget build(BuildContext context) {
    final icon = feedback.changed == true ? Icons.check_circle_outline : Icons.info_outline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(feedback.headline!, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(feedback.message!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run targeted tests to verify they pass**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows refresh completion feedback when query matches feedback context"`

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage hides refresh completion feedback when current query no longer matches"`

Expected: PASS

### Task 3: 全量验证

**Files:**
- Modify: `lib/features/search/application/search_providers.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Test: `test/features/search/application/search_providers_test.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run changed test files**

Run: `flutter test test/features/search/application/search_providers_test.dart`

Expected: PASS

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/application/search_providers.dart`
- `lib/features/search/presentation/search_page.dart`
- `test/features/search/application/search_providers_test.dart`
- `test/features/search/presentation/search_page_test.dart`

Expected: clean diagnostics
