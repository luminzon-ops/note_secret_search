# Search Observability Dominant Hints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 SearchPage 现有搜索观测摘要中补充主导信号与主导字段提示，让顶部观测摘要更容易被快速理解。

**Architecture:** 在 `search_result_explanation.dart` 中扩展 `SearchObservabilitySummary`，把主导信号与主导字段的判断逻辑集中在 helper 层。SearchPage 只做渲染，不自行拼接结论文案。

**Tech Stack:** Flutter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-search-observability-dominant-hints-design.md`
  - 主导信号 / 主导字段提示设计
- Create: `docs/superpowers/plans/2026-04-23-search-observability-dominant-hints.md`
  - 本实现计划
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
  - 扩展 observability summary 结构与主导提示 helper
- Modify: `lib/features/search/presentation/search_page.dart`
  - 渲染主导信号 / 主导字段提示
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
  - 增加 helper 层主导提示测试
- Modify: `test/features/search/presentation/search_page_test.dart`
  - 增加 SearchPage 展示断言

### Task 1: Add helper-level tests for dominant hints

**Files:**
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `lib/features/search/presentation/search_result_explanation.dart`

- [ ] **Step 1: Write the failing unit tests for dominant signal hints**

Add tests that assert:

1. keyword-only result set -> `当前结果主要由关键词命中主导（1 条）。`
2. mixed dual/semantic/keyword set -> correct dominant signal hint
3. signal count ties follow priority `dual > keywordPrimary > semanticAssist`

- [ ] **Step 2: Write the failing unit tests for dominant field hints**

Add tests that assert:

1. semantic title + tags mix -> dominant field hint picks the top count
2. no semantic fields -> dominant field hint is null
3. field count ties follow configured priority

- [ ] **Step 3: Run the helper tests to verify RED**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

Expected: FAIL because dominant hint fields do not exist yet.

- [ ] **Step 4: Implement the minimal helper changes**

In `search_result_explanation.dart`:

1. extend `SearchObservabilitySummary` with `dominantSignalHint`
2. extend `SearchObservabilitySummary` with `dominantFieldHint`
3. compute both hints in `buildSearchObservabilitySummary`

- [ ] **Step 5: Run the helper tests to verify GREEN**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

Expected: PASS

### Task 2: Show dominant hints in SearchPage observability summary

**Files:**
- Modify: `test/features/search/presentation/search_page_test.dart`
- Modify: `lib/features/search/presentation/search_page.dart`

- [ ] **Step 1: Write the failing SearchPage test for dominant hints**

Add a widget test that expects:

1. dominant signal hint is shown in observability summary
2. dominant field hint is shown when semantic fields exist

- [ ] **Step 2: Run the SearchPage test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows dominant signal and dominant field hints in observability summary"`

Expected: FAIL because the new lines are not rendered yet.

- [ ] **Step 3: Implement the minimal SearchPage rendering update**

In `search_page.dart`:

1. render `dominantSignalHint`
2. render `dominantFieldHint` when non-null

- [ ] **Step 4: Run the SearchPage test to verify GREEN**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows dominant signal and dominant field hints in observability summary"`

Expected: PASS

### Task 3: Final verification

**Files:**
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run helper unit tests**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

Expected: PASS

- [ ] **Step 2: Run SearchPage widget tests**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS

- [ ] **Step 3: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/presentation/search_result_explanation.dart`
- `lib/features/search/presentation/search_page.dart`
- `test/features/search/presentation/search_result_explanation_test.dart`
- `test/features/search/presentation/search_page_test.dart`

Expected: clean diagnostics
