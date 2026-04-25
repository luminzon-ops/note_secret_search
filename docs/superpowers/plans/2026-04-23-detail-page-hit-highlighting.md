# Detail Page Hit Highlighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 secret / note 详情页增加字段级命中高亮与一次性轻量滚动，让用户更容易看到搜索命中的位置。

**Architecture:** 新增一个小型 helper 专门负责从 `searchContext` 识别详情页目标字段。`SecretDetailPage` 与 `NoteDetailPage` 只根据该字段枚举决定高亮哪块区域，并在目标存在时通过一次性 `ensureVisible` 做轻量滚动。

**Tech Stack:** Flutter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-detail-page-hit-highlighting-design.md`
  - 详情页命中位置承接设计
- Create: `docs/superpowers/plans/2026-04-23-detail-page-hit-highlighting.md`
  - 本实现计划
- Create: `lib/features/search/presentation/detail_search_hit_target.dart`
  - 从 `searchContext` 识别详情页命中字段的 helper
- Create: `test/features/search/presentation/detail_search_hit_target_test.dart`
  - helper 测试
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
  - secret detail 字段级高亮和一次性滚动
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
  - note detail 字段级高亮和一次性滚动
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
  - secret detail 高亮测试
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`
  - note detail 高亮测试

### Task 1: Add detail-field inference helper

**Files:**
- Create: `test/features/search/presentation/detail_search_hit_target_test.dart`
- Create: `lib/features/search/presentation/detail_search_hit_target.dart`

- [ ] **Step 1: Write the failing tests for field inference**

Add tests that assert:

1. `标题：Bank Account` resolves to secret title and note title
2. `账号：alice@example.com` resolves to secret username
3. `网址：bank.example.com` resolves to secret website
4. `摘要：恢复码备忘` resolves to note summary
5. `正文：backup codes` resolves to note content
6. `标签：backup` resolves to tags
7. unknown prefix resolves to none

- [ ] **Step 2: Run the helper tests to verify RED**

Run: `flutter test test/features/search/presentation/detail_search_hit_target_test.dart`

Expected: FAIL because helper does not exist yet.

- [ ] **Step 3: Write the minimal helper implementation**

Create a small helper with two enums or one shared enum that can represent the supported detail targets.

- [ ] **Step 4: Run the helper tests to verify GREEN**

Run: `flutter test test/features/search/presentation/detail_search_hit_target_test.dart`

Expected: PASS

### Task 2: Add secret detail highlighting

**Files:**
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`

- [ ] **Step 1: Write the failing secret detail highlight tests**

Add tests that assert:

1. `searchContext: '账号：alice@example.com'` marks the username row as highlighted
2. `searchContext: '备注：bank note'` marks the note row as highlighted
3. `searchContext: '未知：x'` does not mark any row as highlighted

Use a stable finder strategy such as dedicated text labels or test-visible markers.

- [ ] **Step 2: Run the secret detail tests to verify RED**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`

Expected: FAIL because highlight state is not rendered yet.

- [ ] **Step 3: Implement minimal secret detail highlighting and one-time scroll**

In `secret_detail_page.dart`:

1. infer the matched target from `searchContext`
2. wrap supported rows in a reusable highlight container
3. attach `GlobalKey` to supported rows
4. after first frame, call `Scrollable.ensureVisible` once for the matched target when recognized

- [ ] **Step 4: Run the secret detail tests to verify GREEN**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`

Expected: PASS

### Task 3: Add note detail highlighting

**Files:**
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Write the failing note detail highlight tests**

Add tests that assert:

1. `searchContext: '摘要：summary'` marks the summary block as highlighted
2. `searchContext: '正文：backup codes'` marks the content block as highlighted
3. `searchContext: '未知：x'` does not mark any note section as highlighted

- [ ] **Step 2: Run the note detail tests to verify RED**

Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: FAIL because highlight state is not rendered yet.

- [ ] **Step 3: Implement minimal note detail highlighting and one-time scroll**

In `note_detail_page.dart`:

1. infer matched target from `searchContext`
2. wrap title / summary / tags / content sections in reusable highlight containers
3. attach `GlobalKey` to supported sections
4. after first frame, call `Scrollable.ensureVisible` once for the matched target when recognized

- [ ] **Step 4: Run the note detail tests to verify GREEN**

Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: PASS

### Task 4: Verification

**Files:**
- Create: `lib/features/search/presentation/detail_search_hit_target.dart`
- Create: `test/features/search/presentation/detail_search_hit_target_test.dart`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`

- [ ] **Step 1: Run all relevant test files**

Run:

- `flutter test test/features/search/presentation/detail_search_hit_target_test.dart`
- `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
- `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/presentation/detail_search_hit_target.dart`
- `lib/features/secrets/presentation/secret_detail_page.dart`
- `lib/features/notes/presentation/note_detail_page.dart`
- `test/features/search/presentation/detail_search_hit_target_test.dart`
- `test/features/secrets/presentation/secret_detail_page_test.dart`
- `test/features/notes/presentation/note_detail_page_test.dart`

Expected: clean diagnostics
