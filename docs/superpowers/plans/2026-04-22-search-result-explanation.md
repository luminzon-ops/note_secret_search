# Search Result Explanation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增强 SearchPage 的结果质量解释，在顶部给出列表级解释总览，并为每条结果补充命中类型轻量标签。

**Architecture:** 把结果解释判定逻辑抽到独立 helper 中，避免继续膨胀 `search_page.dart`。SearchPage 负责渲染增强后的总览文案与命中类型标签，判定完全基于现有 `matchSources` 和 unified results 前 5 条，不改搜索排序算法。

**Tech Stack:** Flutter, Riverpod, flutter_test

---

## File Structure

- Create: `lib/features/search/presentation/search_result_explanation.dart`
  - 命中类型标签与列表级解释摘要 helper
- Modify: `lib/features/search/presentation/search_page.dart`
  - 接入增强后的顶部总览与结果项轻量标签
- Modify: `test/features/search/presentation/search_page_test.dart`
  - 新增列表级解释与命中类型标签测试

### Task 1: 结果解释 helper

**Files:**
- Create: `lib/features/search/presentation/search_result_explanation.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing widget test for mixed dual-hit dominant overview**

```dart
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
            _result('a', {SearchMatchSource.keyword, SearchMatchSource.semantic}),
            _result('b', {SearchMatchSource.keyword, SearchMatchSource.semantic}),
            _result('c', {SearchMatchSource.keyword}),
          ],
        ),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('当前前排结果以双命中为主，关键词与语义信号共同参与排序。'), findsOneWidget);
  expect(find.text('前 3 条中：双命中 2 条，关键词优先 1 条，语义辅助 0 条。'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows dual-hit dominant overview summary"`

Expected: FAIL because the new overview copy does not exist yet.

- [ ] **Step 3: Write the failing widget test for keyword-dominant overview**

```dart
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
            _result('a', {SearchMatchSource.keyword}),
            _result('b', {SearchMatchSource.keyword}),
            _result('c', {SearchMatchSource.semantic}),
          ],
        ),
        semanticSearchResultsProvider.overrideWith(
          (ref) async => [
            _semanticResult('c'),
          ],
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('当前前排结果以关键词命中为主，语义信号主要用于补充排序。'), findsOneWidget);
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows keyword-dominant overview when semantic only assists"`

Expected: FAIL because keyword-dominant summary logic is not implemented yet.

- [ ] **Step 5: Write the failing widget test for semantic-dominant overview**

```dart
testWidgets('SearchPage shows semantic-dominant overview when semantic-assisted results lead', (tester) async {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchQueryProvider.overrideWith((ref) => 'bank'),
        unifiedSearchResultsProvider.overrideWith(
          (ref) async => [
            _result('a', {SearchMatchSource.semantic}),
            _result('b', {SearchMatchSource.semantic}),
          ],
        ),
        semanticSearchResultsProvider.overrideWith(
          (ref) async => [
            _semanticResult('a'),
            _semanticResult('b'),
          ],
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('当前前排结果更多依赖语义召回，适合继续检查命中摘要与上下文。'), findsOneWidget);
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows semantic-dominant overview when semantic-assisted results lead"`

Expected: FAIL because semantic-dominant summary logic is not implemented yet.

- [ ] **Step 7: Write minimal helper implementation**

```dart
enum SearchResultHitLabel {
  dual,
  keywordPrimary,
  semanticAssist,
}

SearchResultHitLabel classifySearchResultHit(SearchResultItem item) {
  final hasKeyword = item.matchSources.contains(SearchMatchSource.keyword);
  final hasSemantic = item.matchSources.contains(SearchMatchSource.semantic);

  if (hasKeyword && hasSemantic) {
    return SearchResultHitLabel.dual;
  }
  if (hasKeyword) {
    return SearchResultHitLabel.keywordPrimary;
  }
  return SearchResultHitLabel.semanticAssist;
}
```

```dart
class SearchResultExplanationSummary {
  const SearchResultExplanationSummary({
    required this.headline,
    required this.breakdown,
  });

  final String headline;
  final String breakdown;
}
```

- [ ] **Step 8: Run targeted tests to verify they pass**

Run the three tests above.

Expected: PASS

### Task 2: SearchPage 接入总览增强与标签

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing widget test for dual-hit tag**

```dart
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
            _result('a', {SearchMatchSource.keyword, SearchMatchSource.semantic}),
          ],
        ),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('双命中'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows dual-hit chip on mixed-match results"`

Expected: FAIL because chips are not rendered yet.

- [ ] **Step 3: Write the failing widget test for keyword-primary and semantic-assist tags**

```dart
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
            _result('a', {SearchMatchSource.keyword}),
            _result('b', {SearchMatchSource.semantic}),
          ],
        ),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('关键词优先'), findsOneWidget);
  expect(find.text('语义辅助'), findsOneWidget);
});
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows keyword-primary and semantic-assist chips"`

Expected: FAIL because chips are not rendered yet.

- [ ] **Step 5: Write minimal SearchPage integration**

```dart
_SearchPipelineSummaryCard(
  unifiedResults: unifiedResultsAsync.requireValue,
  semanticResults: semanticResultsAsync.requireValue,
)
```

Update `_SearchPipelineSummaryCard` to consume `buildSearchResultExplanationSummary(...)`.

```dart
Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    Chip(label: Text(resolveSearchResultHitLabel(item))),
  ],
)
```

- [ ] **Step 6: Run targeted tests to verify they pass**

Run the two chip tests above plus the overview tests.

Expected: PASS

### Task 3: Full verification

**Files:**
- Create: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run SearchPage test file**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/presentation/search_result_explanation.dart`
- `lib/features/search/presentation/search_page.dart`
- `test/features/search/presentation/search_page_test.dart`

Expected: clean diagnostics
