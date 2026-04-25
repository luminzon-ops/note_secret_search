# Semantic Explanation Tiering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为当前语义结果增加“高质量语义命中 / 辅助语义命中”的解释分层，并在 SearchPage 顶部总览与结果项解释中同时体现。

**Architecture:** 在 `search_result_explanation.dart` 中集中新增语义解释分层 helper，复用现有 `semanticHitField` 作为主要分层依据。SearchPage 顶部检索链路总览补充高质量 / 辅助语义命中数量，结果项 `排序依据` 区块同步加入分层说明，但不改底层召回和排序逻辑。

**Tech Stack:** Flutter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-semantic-explanation-tiering-design.md`
  - 语义解释分层设计文档
- Create: `docs/superpowers/plans/2026-04-23-semantic-explanation-tiering.md`
  - 本实现计划
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
  - 新增高质量 / 辅助语义分层 helper
- Modify: `lib/features/search/presentation/search_page.dart`
  - 顶部总览补充分层说明，结果项排序依据复用新 helper
- Modify: `test/features/search/presentation/search_page_test.dart`
  - 新增顶部总览与结果项分层测试

### Task 1: Add semantic explanation tier helpers

**Files:**
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing test for overview tiering summary**

Add a widget test that renders SearchPage with:

1. one semantic/title hit
2. one semantic/tags hit

and expects a top summary sentence such as:

- `当前语义结果中，高质量语义命中 1 条，辅助语义命中 1 条。`

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows semantic tier counts in the top summary when semantic signals are present"`

Expected: FAIL because the overview tiering summary does not exist yet.

- [ ] **Step 3: Add minimal helper types/functions**

In `search_result_explanation.dart`, add:

1. semantic explanation tier enum
2. function to classify tier from `SearchResultItem`
3. function to count tiers from unified results

Expected pattern:

```dart
enum SemanticExplanationTier { highQuality, assist, none }

SemanticExplanationTier classifySemanticExplanationTier(SearchResultItem item) { ... }
```

- [ ] **Step 4: Run the overview test again**

Expected: still FAIL until SearchPage uses the helper.

### Task 2: Show tiering in SearchPage overview and item explanations

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing test for high-quality semantic explanation on an item**

Add a widget test that renders a semantic/title hit and expects item-level explanation text:

- `• 高质量语义命中：标题属于高可信语义字段`

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows high-quality semantic explanation for title-based semantic hits"`

Expected: FAIL because the item-level tiering copy does not exist yet.

- [ ] **Step 3: Write the failing test for assist semantic explanation on an item**

Add a widget test that renders a semantic/tags or semantic/noteBody hit and expects item-level explanation text:

- `• 辅助语义命中：标签属于辅助语义线索`

- [ ] **Step 4: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows assist semantic explanation for lower-priority semantic fields"`

Expected: FAIL because the item-level assist copy does not exist yet.

- [ ] **Step 5: Write the failing test for keyword-only not showing tiering text**

Add a widget test that renders keyword-only results and asserts no `高质量语义命中` or `辅助语义命中` text appears.

- [ ] **Step 6: Run the test to verify RED or existing behavior**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage does not show semantic tiering copy for keyword-only results"`

Expected: PASS or FAIL depending on current copy; keep it explicit.

- [ ] **Step 7: Implement the minimal SearchPage tiering UI**

In `search_page.dart`:

1. top summary adds the tier count sentence when semantic results participate
2. ranking reason lines add one extra line for high-quality tier or assist tier
3. keyword-only paths do not add semantic tiering copy

- [ ] **Step 8: Run the targeted tests to verify GREEN**

Run the four tests from this task.

Expected: PASS

### Task 3: Verification

**Files:**
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run SearchPage tests**

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
