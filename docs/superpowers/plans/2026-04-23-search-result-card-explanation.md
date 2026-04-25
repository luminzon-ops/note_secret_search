# Search Result Card Explanation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 SearchPage 的单条结果卡片增加轻量结论式解释，让用户更快理解每条结果的命中质量与来源。

**Architecture:** 在 `search_result_explanation.dart` 中新增结果卡片级解释 helper，复用已有 hit label / semantic tier 判定逻辑。SearchPage 只渲染单条 explanation，不引入新状态或复杂组件。

**Tech Stack:** Flutter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-search-result-card-explanation-design.md`
- Create: `docs/superpowers/plans/2026-04-23-search-result-card-explanation.md`
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

### Task 1: Add failing helper tests for result-card explanation

**Files:**
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `lib/features/search/presentation/search_result_explanation.dart`

- [ ] **Step 1: Write failing helper tests**

Add tests covering:

1. dual + high-quality semantic -> `这条结果同时命中关键词与高质量语义字段，可优先查看。`
2. dual + assist semantic -> `这条结果同时命中关键词，但语义信号主要来自辅助字段，建议结合预览确认。`
3. keyword-only -> `这条结果主要由关键词命中进入结果。`
4. semantic-only + high-quality -> `这条结果主要由高质量语义命中支持，适合优先检查。`
5. semantic-only + assist -> `这条结果主要由辅助语义线索召回，建议谨慎判断。`

- [ ] **Step 2: Run helper tests to verify RED**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

Expected: FAIL because the new helper does not exist yet.

- [ ] **Step 3: Implement minimal helper**

Add a helper such as `buildSearchResultCardExplanation(SearchResultItem item)` in `search_result_explanation.dart`, reusing existing classification functions.

- [ ] **Step 4: Re-run helper tests to verify GREEN**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

Expected: PASS

### Task 2: Show explanation on SearchPage result cards

**Files:**
- Modify: `test/features/search/presentation/search_page_test.dart`
- Modify: `lib/features/search/presentation/search_page.dart`

- [ ] **Step 1: Write failing widget test for result-card explanation**

Add a SearchPage widget test that expects the result card to show one of the new explanation lines for a known fixture.

- [ ] **Step 2: Run focused widget test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows result-card explanation for high-quality dual-hit result"`

Expected: FAIL because the card does not render the explanation yet.

- [ ] **Step 3: Implement minimal UI rendering**

Render the new explanation line between preview text and the `排序依据` block.

- [ ] **Step 4: Re-run focused widget test to verify GREEN**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows result-card explanation for high-quality dual-hit result"`

Expected: PASS

### Task 3: Final verification

**Files:**
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run helper tests**

Run: `flutter test test/features/search/presentation/search_result_explanation_test.dart`

Expected: PASS

- [ ] **Step 2: Run SearchPage tests**

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
