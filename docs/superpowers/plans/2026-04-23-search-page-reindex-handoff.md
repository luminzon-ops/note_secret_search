# Search Page Reindex Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 SearchPage 承接设置页保存后“需要重新索引但尚未刷新”的状态，并提供立即刷新索引入口。

**Architecture:** 在 search providers 中新增一个轻量 handoff state，专门表示“设置已保存但语义索引尚未刷新”的跨页提示。SearchSettingsPage 在用户带着未刷新状态返回搜索页时写入该 state，SearchPage 渲染一张顶部承接卡片并复用现有 `indexPendingAndRefresh()` 流程完成刷新后清除状态。

**Tech Stack:** Flutter, Riverpod, GoRouter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-search-page-reindex-handoff-design.md`
  - 搜索页承接卡片设计文档
- Create: `docs/superpowers/plans/2026-04-23-search-page-reindex-handoff.md`
  - 本实现计划
- Modify: `lib/features/search/application/search_providers.dart`
  - 新增 pending-reindex handoff state/provider
- Modify: `lib/features/search/presentation/search_settings_page.dart`
  - 在 `返回搜索` 时写入 handoff state
- Modify: `lib/features/search/presentation/search_page.dart`
  - 渲染搜索页顶部承接卡片并处理刷新动作
- Modify: `test/features/search/presentation/search_page_test.dart`
  - 新增搜索页承接卡片测试

### Task 1: Pending-reindex handoff state

**Files:**
- Modify: `lib/features/search/application/search_providers.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing test for showing the SearchPage handoff card**

Add a widget test that overrides the new handoff provider with a visible state and expects:

- `设置已保存，但语义结果还没刷新`
- `你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。`
- `立即刷新索引`

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows pending-reindex handoff card when settings were saved without refreshing index"`

Expected: FAIL because the provider/card do not exist yet.

- [ ] **Step 3: Add the minimal handoff state**

Add a lightweight state in `search_providers.dart`, for example:

```dart
class SearchPendingReindexHandoffState {
  const SearchPendingReindexHandoffState({required this.visible, this.message});
  const SearchPendingReindexHandoffState.hidden() : visible = false, message = null;

  final bool visible;
  final String? message;
}

final searchPendingReindexHandoffProvider = StateProvider<SearchPendingReindexHandoffState>(
  (ref) => const SearchPendingReindexHandoffState.hidden(),
);
```

- [ ] **Step 4: Run the test again**

Run the same test from Step 2.

Expected: still FAIL because SearchPage does not render the card yet.

### Task 2: SearchPage renders and clears the handoff card

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing test for triggering refresh from the handoff card**

Add a widget test that:

1. injects a visible handoff state
2. overrides `searchIndexControllerProvider` with `_RecordingSearchIndexController`
3. taps `立即刷新索引`
4. expects `refreshCalls == 1`

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage pending-reindex handoff action triggers refresh flow"`

Expected: FAIL because the action is not wired yet.

- [ ] **Step 3: Write the failing test for clearing the handoff state on success**

Add a widget test that:

1. injects a visible handoff state
2. uses a recording controller with success path
3. taps `立即刷新索引`
4. expects the handoff card to disappear after `pump()` / `pumpAndSettle()`

- [ ] **Step 4: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage clears pending-reindex handoff card after refresh starts successfully"`

Expected: FAIL because the state is not cleared yet.

- [ ] **Step 5: Write the failing test for preserving the card on failure**

Add a widget test that:

1. injects a visible handoff state
2. uses a recording controller with `error`
3. taps `立即刷新索引`
4. expects the handoff card to remain visible

- [ ] **Step 6: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage keeps pending-reindex handoff card when refresh trigger fails"`

Expected: FAIL because failure preservation is not implemented yet.

- [ ] **Step 7: Implement the minimal SearchPage handoff card**

In `search_page.dart`:

1. watch `searchPendingReindexHandoffProvider`
2. render a small card above the search status card
3. show the fixed title/body copy from the spec
4. wire `立即刷新索引` to `searchIndexControllerProvider.indexPendingAndRefresh()`
5. clear the handoff provider only after success path starts
6. keep the state on failure

- [ ] **Step 8: Run the targeted tests to verify GREEN**

Run the three tests from this task.

Expected: PASS

### Task 3: SearchSettingsPage writes the handoff state on return

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing test for not showing the card when no handoff state exists**

Add a widget test that renders `SearchPage` with the default hidden handoff state and asserts the handoff title is absent.

- [ ] **Step 2: Run the test to verify RED or existing behavior**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage does not show pending-reindex handoff card when no handoff state exists"`

Expected: PASS if behavior already holds, otherwise FAIL.

- [ ] **Step 3: Update SearchSettingsPage return flow to write the handoff state**

When `_showPostSaveReindexActions == true` and the user taps `返回搜索`, write:

```dart
ref.read(searchPendingReindexHandoffProvider.notifier).state =
  const SearchPendingReindexHandoffState(
    visible: true,
    message: '你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。',
  );
```

Then navigate back to search.

- [ ] **Step 4: Run the full SearchPage test file**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS

### Task 4: Verification

**Files:**
- Modify: `lib/features/search/application/search_providers.dart`
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run changed SearchPage tests**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS

- [ ] **Step 2: Run SearchSettingsPage tests**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart`

Expected: PASS

- [ ] **Step 3: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/application/search_providers.dart`
- `lib/features/search/presentation/search_settings_page.dart`
- `lib/features/search/presentation/search_page.dart`
- `test/features/search/presentation/search_page_test.dart`

Expected: clean diagnostics
