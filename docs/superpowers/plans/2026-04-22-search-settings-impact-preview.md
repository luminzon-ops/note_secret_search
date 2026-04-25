# Search Settings Impact Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 SearchSettingsPage 中根据草稿态设置改动动态提示哪些修改会立即影响搜索结果，哪些需要重新索引后生效，并给出当前建议。

**Architecture:** 为 SearchScope 和 SearchIndexSettings 增加页面内草稿态，通过 helper 比较草稿与已保存配置，生成影响预期 view model。SearchSettingsPage 渲染单张结果预期提示卡，不引入复杂全局草稿系统，也不改搜索算法。

**Tech Stack:** Flutter, Riverpod, flutter_test

---

## File Structure

- Create: `lib/features/search/presentation/search_settings_impact_preview.dart`
  - 草稿 diff 与结果预期 helper
- Modify: `lib/features/search/presentation/search_settings_page.dart`
  - 接入页面内草稿态与结果预期提示卡
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
  - 新增草稿态结果预期提示测试

### Task 1: 结果预期 helper

**Files:**
- Create: `lib/features/search/presentation/search_settings_impact_preview.dart`
- Test: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Write the failing test for default guidance without draft changes**

```dart
testWidgets('SearchSettingsPage shows default impact guidance when there are no draft changes', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        semanticSearchReadinessProvider.overrideWith((ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready')),
        searchIndexStatusProvider.overrideWith((ref) async => const SearchIndexStatus(engineReady: true, engineReason: 'ready', hasActiveEmbeddingModel: true, pendingItems: <SearchIndexPendingItem>[])),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('这些设置会如何影响结果'), findsOneWidget);
  expect(find.text('检索范围类设置会立即影响结果；索引内容类设置在你下次重建索引后生效。'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows default impact guidance when there are no draft changes"`

Expected: FAIL because the impact preview card does not exist yet.

- [ ] **Step 3: Write the failing test for immediate-impact draft changes**

```dart
testWidgets('SearchSettingsPage shows immediate-impact guidance for scope draft changes', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        semanticSearchReadinessProvider.overrideWith((ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready')),
        searchIndexStatusProvider.overrideWith((ref) async => const SearchIndexStatus(engineReady: true, engineReason: 'ready', hasActiveEmbeddingModel: true, pendingItems: <SearchIndexPendingItem>[])),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('检索范围控制'), 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('检索标题').first);
  await tester.pumpAndSettle();

  expect(find.text('你当前的草稿会立即影响搜索结果。保存后可以直接回到搜索页查看变化。'), findsOneWidget);
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows immediate-impact guidance for scope draft changes"`

Expected: FAIL because draft diff detection is not implemented yet.

- [ ] **Step 5: Write the failing test for reindex-required draft changes**

```dart
testWidgets('SearchSettingsPage shows reindex guidance for index-content draft changes', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        semanticSearchReadinessProvider.overrideWith((ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready')),
        searchIndexStatusProvider.overrideWith((ref) async => const SearchIndexStatus(engineReady: true, engineReason: 'ready', hasActiveEmbeddingModel: true, pendingItems: <SearchIndexPendingItem>[])),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.text('索引密码附注').first);
  await tester.pumpAndSettle();

  expect(find.text('你当前的草稿会影响语义索引内容。保存后需要重新索引，语义结果才会更新。'), findsOneWidget);
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows reindex guidance for index-content draft changes"`

Expected: FAIL because reindex-required diff detection is not implemented yet.

- [ ] **Step 7: Write the failing test for mixed changes with pending items**

```dart
testWidgets('SearchSettingsPage shows mixed guidance and pending-item recommendation', (tester) async {
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
        semanticSearchReadinessProvider.overrideWith((ref) async => const SemanticSearchReadiness(ready: true, reason: 'ready')),
        searchIndexStatusProvider.overrideWith((ref) async => SearchIndexStatus(engineReady: true, engineReason: 'ready', hasActiveEmbeddingModel: true, pendingItems: [pendingItem])),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.text('索引密码附注').first);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('检索范围控制'), 300, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('检索标题').first);
  await tester.pumpAndSettle();

  expect(find.text('你当前的草稿包含两类影响：部分改动会立即影响结果，部分改动需要重新索引后生效。'), findsOneWidget);
  expect(find.text('当前已有待索引内容，建议保存后直接刷新索引。'), findsOneWidget);
});
```

- [ ] **Step 8: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows mixed guidance and pending-item recommendation"`

Expected: FAIL because mixed-impact guidance is not implemented yet.

- [ ] **Step 9: Write minimal helper implementation**

```dart
class SearchSettingsImpactPreview {
  const SearchSettingsImpactPreview({
    required this.headline,
    required this.description,
    required this.immediateItems,
    required this.reindexItems,
    this.recommendation,
  });

  final String headline;
  final String description;
  final List<String> immediateItems;
  final List<String> reindexItems;
  final String? recommendation;
}
```

```dart
SearchSettingsImpactPreview buildSearchSettingsImpactPreview({
  required SearchScopeConfig savedScope,
  required SearchScopeConfig draftScope,
  required SearchIndexSettings savedIndexSettings,
  required SearchIndexSettings draftIndexSettings,
  required SearchIndexStatus indexStatus,
}) {
  // return default / immediate / reindex / mixed guidance
}
```

- [ ] **Step 10: Run targeted tests to verify they pass**

Run the four tests above.

Expected: PASS

### Task 2: SearchSettingsPage 接入草稿态与预期提示

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Introduce page-local draft state**

Use `ConsumerStatefulWidget` for `SearchSettingsPage` and keep local draft fields:

```dart
SearchScopeConfig? _draftScope;
SearchIndexSettings? _draftIndexSettings;
```

Initialize draft values from async providers when data becomes available and when no user edits are in progress.

- [ ] **Step 2: Update settings cards to edit draft instead of immediately persisting**

Expected pattern:

```dart
onChanged: (value) {
  setState(() {
    _draftIndexSettings = draft.copyWith(includeSecretNotes: value);
  });
}
```

```dart
onChanged: (value) {
  setState(() {
    _draftScope = draft.copyWith(includeTitle: value);
  });
}
```

- [ ] **Step 3: Add a save action and impact preview card**

Render the impact preview card when saved and draft values are available.

Add save entry points for scope/index settings using existing controllers.

- [ ] **Step 4: Run full SearchSettingsPage test file**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart`

Expected: PASS

### Task 3: 保存后的重索引行动条闭环

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Write the failing test for showing the post-save action bar**

Add a widget test that:

1. toggles `索引密码附注`
2. taps `保存索引设置`
3. expects:
   - `设置已保存，语义结果需要刷新索引后更新。`
   - `立即刷新`
   - `返回搜索`

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows post-save reindex action bar after saving index changes"`

Expected: FAIL because the post-save action bar does not exist yet.

- [ ] **Step 3: Write the failing test for the refresh action**

Add a widget test that saves an index-setting diff, taps `立即刷新`, and asserts the recording controller increments `refreshCalls`.

- [ ] **Step 4: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage post-save reindex action bar triggers refresh flow"`

Expected: FAIL because the refresh action is not wired from the post-save action bar.

- [ ] **Step 5: Write the failing test for returning to search**

Add a router-backed widget test that:

1. starts on `/settings`
2. saves an index-setting diff
3. taps `返回搜索`
4. expects `search page`

- [ ] **Step 6: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage post-save reindex action bar can return to search"`

Expected: FAIL because the action bar navigation is not wired yet.

- [ ] **Step 7: Write the failing test for immediate-only saves**

Add a widget test that saves only an immediate-impact scope diff and asserts the post-save action bar is absent.

- [ ] **Step 8: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage does not show post-save reindex action bar for immediate-only changes"`

Expected: FAIL because the page does not distinguish post-save reindex vs immediate-only saves yet.

- [ ] **Step 9: Implement the minimal post-save action bar flow**

In `SearchSettingsPage`:

1. add page-local state for whether to show the post-save action bar
2. compute `needsReindex` from `buildSearchSettingsImpactPreview(...).reindexItems`
3. after successful save, show the action bar only when `needsReindex == true`
4. clear the action bar when the user edits drafts again
5. wire `立即刷新` to `searchIndexControllerProvider.indexPendingAndRefresh()`
6. wire `返回搜索` to `context.pop()` with `context.go('/')` fallback

- [ ] **Step 10: Run the new targeted tests to verify GREEN**

Run:

- `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows post-save reindex action bar after saving index changes"`
- `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage post-save reindex action bar triggers refresh flow"`
- `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage post-save reindex action bar can return to search"`
- `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage does not show post-save reindex action bar for immediate-only changes"`

Expected: PASS

### Task 4: Verification

**Files:**
- Create: `lib/features/search/presentation/search_settings_impact_preview.dart`
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Run changed test file**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/presentation/search_settings_impact_preview.dart`
- `lib/features/search/presentation/search_settings_page.dart`
- `test/features/search/presentation/search_settings_page_test.dart`

Expected: clean diagnostics
