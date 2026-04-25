# Search Observability Semantic-Only Filtering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 SearchPage 顶部观测摘要中显示 semantic-only 过滤统计，让最近新增的过滤策略可见。

**Architecture:** 不修改 search service 或 fusion service 返回结构，只在 `search_result_explanation.dart` 中基于 `semanticResults` 与 `unifiedResults` 做派生统计，再由 `search_page.dart` 渲染新增文案。保持 UI 改动最小，继续复用现有 observability block。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-25-search-observability-semantic-only-filtering-design.md`
- Create: `docs/superpowers/plans/2026-04-25-search-observability-semantic-only-filtering.md`
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

### Task 1: Add failing helper tests for semantic-only filtering stats

**Files:**
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`

- [ ] **Step 1: Write the failing helper test for semantic-only filtering stats**

Construct:

1. semantic results with multiple items
2. unified results that keep only part of the semantic-only items

Assert a new observability summary line like:

- `语义过滤：semantic-only 候选 3 条，保留 1 条，过滤 2 条。`

- [ ] **Step 2: Run the targeted helper test to verify RED**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart --plain-name "buildSearchObservabilitySummary includes semantic-only filtering stats when semantic-only results are filtered"`

Expected: FAIL because the summary does not include that line yet.

### Task 2: Render filtering stats in SearchPage observability block

**Files:**
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing widget test for SearchPage observability filtering text**

Render SearchPage with semantic results count greater than retained semantic-only unified results and expect the filtering text to appear.

- [ ] **Step 2: Run the targeted widget test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows semantic-only filtering stats in observability summary"`

Expected: FAIL because the observability UI does not show the filtering text yet.

- [ ] **Step 3: Implement minimal helper + UI wiring**

Add a nullable `semanticOnlyFilteringBreakdown` field to the summary model, compute it in helper code, and render it in the expanded observability section.

- [ ] **Step 4: Re-run targeted tests to verify GREEN**

### Task 3: Final verification

**Files:**
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run presentation helper tests**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

- [ ] **Step 2: Run SearchPage tests**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

- [ ] **Step 3: Run analyze**

Run: `flutter analyze`

- [ ] **Step 4: Check diagnostics on changed files**

Run LSP diagnostics on changed files.
