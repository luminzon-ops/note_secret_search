# Search Observability Reminder Hints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 SearchPage 的搜索观测摘要中增加一条轻量提醒型结论，帮助用户更快判断当前结果质量倾向。

**Architecture:** 在 `search_result_explanation.dart` 中扩展 `SearchObservabilitySummary`，把提醒型结论规则集中在 helper 层。SearchPage 只渲染提醒文本，不在 widget 层判断提醒规则。

**Tech Stack:** Flutter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-search-observability-reminder-hints-design.md`
  - 提醒型结论设计
- Create: `docs/superpowers/plans/2026-04-23-search-observability-reminder-hints.md`
  - 本实现计划
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
  - 扩展 observability summary 的提醒型结论
- Modify: `lib/features/search/presentation/search_page.dart`
  - 渲染提醒型结论
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
  - 新增 helper 层提醒测试
- Modify: `test/features/search/presentation/search_page_test.dart`
  - 新增 SearchPage 展示测试

### Task 1: Add helper-level tests for reminder hints

**Files:**
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `lib/features/search/presentation/search_result_explanation.dart`

- [ ] **Step 1: Write the failing unit tests for reminder rules**

Add tests that assert:

1. keyword-dominant weak-semantic case -> `当前结果主要由关键词命中主导，语义链路参与较弱。`
2. assist-field dominant case -> `当前语义参与主要来自辅助字段，建议谨慎判断结果质量。`
3. high-value field + strong semantic case -> `当前语义命中集中在高价值字段，可优先检查前排结果。`
4. no rule matched -> reminder is null
5. if multiple rules could match, only the highest-priority one is returned

- [ ] **Step 2: Run the helper tests to verify RED**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

Expected: FAIL because `reminderHint` does not exist yet.

- [ ] **Step 3: Implement the minimal helper changes**

In `search_result_explanation.dart`:

1. extend `SearchObservabilitySummary` with `reminderHint`
2. compute reminder hint inside `buildSearchObservabilitySummary`
3. preserve the rule priority order exactly as defined in the spec

- [ ] **Step 4: Run the helper tests to verify GREEN**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

Expected: PASS

### Task 2: Show reminder hint in SearchPage observability summary

**Files:**
- Modify: `test/features/search/presentation/search_page_test.dart`
- Modify: `lib/features/search/presentation/search_page.dart`

- [ ] **Step 1: Write the failing SearchPage test for reminder hint**

Add a widget test that expects a reminder line such as:

- `当前语义参与主要来自辅助字段，建议谨慎判断结果质量。`

in the observability summary.

- [ ] **Step 2: Run the SearchPage test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows reminder hint in observability summary when semantic participation is assist-field driven"`

Expected: FAIL because the reminder line is not rendered yet.

- [ ] **Step 3: Implement the minimal SearchPage rendering update**

In `search_page.dart`:

1. render `summary.reminderHint` when it is non-null

- [ ] **Step 4: Run the SearchPage test to verify GREEN**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows reminder hint in observability summary when semantic participation is assist-field driven"`

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
