# Search Observability Collapsible Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 SearchPage 的搜索观测摘要默认保持紧凑，只在用户展开后显示次级诊断信息。

**Architecture:** 保持 `SearchObservabilitySummary` 只提供文本内容，不引入新的 helper 状态对象。折叠/展开状态放在 `search_page.dart` 的 widget 层，以最小改动控制默认可见行和次级详情区块。

**Tech Stack:** Flutter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-search-observability-collapsible-design.md`
- Create: `docs/superpowers/plans/2026-04-23-search-observability-collapsible.md`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

### Task 1: Add failing widget tests for compact observability summary

**Files:**
- Modify: `test/features/search/presentation/search_page_test.dart`
- Modify: `lib/features/search/presentation/search_page.dart`

- [ ] **Step 1: Write the failing compact-state widget test**

Add a widget test that verifies the observability summary shows by default:

- `命中结构：...`
- `当前结果主要由...主导...`
- reminder line when present

and hides by default:

- `语义分层：...`
- `字段分布：...`
- `当前语义命中主要集中在...字段...`

Also expect the affordance text:

- `展开更多观测`

- [ ] **Step 2: Run the focused widget test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage keeps observability summary compact by default"`

Expected: FAIL because all observability lines are currently always visible.

- [ ] **Step 3: Write the failing expand-collapse widget test**

Add a widget test that taps `展开更多观测`, expects secondary diagnostics to appear, then taps `收起观测详情` and expects them to disappear again.

- [ ] **Step 4: Run the focused expand-collapse widget test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage can expand and collapse secondary observability diagnostics"`

Expected: FAIL because no expand/collapse control exists yet.

### Task 2: Implement compact/collapsible observability summary UI

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Add minimal widget state for observability expansion**

In `search_page.dart`, store a local expansion boolean in `_SearchPipelineSummaryCard` using a small `StatefulWidget` conversion or a tightly scoped stateful wrapper.

- [ ] **Step 2: Render only primary lines by default**

Keep visible by default:

- `summary.hitBreakdown`
- `summary.dominantSignalHint`
- `summary.reminderHint` when non-null

- [ ] **Step 3: Render secondary lines only when expanded**

Move these behind expansion:

- `summary.semanticTierBreakdown`
- `summary.semanticFieldBreakdown`
- `summary.dominantFieldHint`

- [ ] **Step 4: Add the expand/collapse affordance**

Render a text button or equivalent lightweight action:

- collapsed: `展开更多观测`
- expanded: `收起观测详情`

- [ ] **Step 5: Run the focused widget tests to verify GREEN**

Run:

- `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage keeps observability summary compact by default"`
- `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage can expand and collapse secondary observability diagnostics"`

Expected: PASS

### Task 3: Final verification

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run SearchPage widget tests**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/presentation/search_page.dart`
- `test/features/search/presentation/search_page_test.dart`

Expected: clean diagnostics
