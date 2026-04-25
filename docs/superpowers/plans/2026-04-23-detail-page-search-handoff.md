# Detail Page Search Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增强 secret / note 详情页顶部“来自搜索”卡片，让用户能更直观地看到命中方式、查询词和命中说明。

**Architecture:** 复用 `SecretDetailPage` 和 `NoteDetailPage` 中已存在的搜索承接卡片，不新增 provider、不回查搜索页状态。仅对现有卡片结构和文案做保守增强：把标题与命中方式拆开，并将 `searchContext` 用“命中说明”展示。

**Tech Stack:** Flutter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-detail-page-search-handoff-design.md`
  - 详情页搜索承接卡片增强设计
- Create: `docs/superpowers/plans/2026-04-23-detail-page-search-handoff.md`
  - 本实现计划
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
  - 增强 secret detail 顶部搜索卡片文案结构
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
  - 增强 note detail 顶部搜索卡片文案结构
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
  - 更新 secret detail 搜索承接测试
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`
  - 更新 note detail 搜索承接测试

### Task 1: Update secret detail search handoff card

**Files:**
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`

- [ ] **Step 1: Write the failing test for enhanced secret detail search handoff card**

Update the existing secret detail test so it expects:

- `来自搜索`
- `命中方式：双命中`
- `查询词：Bank Account`
- `命中说明：标题：Bank Account`

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart --plain-name "SecretDetailPage shows enhanced search handoff card when opened from search"`

Expected: FAIL because the current page still renders `来自搜索 · 双命中` and `命中上下文`.

- [ ] **Step 3: Implement the minimal secret detail card update**

In `secret_detail_page.dart`:

1. change the first line to standalone `来自搜索`
2. render `命中方式：...` only when `searchSource` exists
3. keep `查询词：...`
4. rename `命中上下文：...` to `命中说明：...`

- [ ] **Step 4: Run the secret detail tests to verify GREEN**

Run: `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`

Expected: PASS

### Task 2: Update note detail search handoff card

**Files:**
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Write the failing test for enhanced note detail search handoff card**

Update the existing note detail test so it expects:

- `来自搜索`
- `命中方式：关键词优先`
- `查询词：Recovery Note`
- `命中说明：标题：Recovery Note`

Keep the semantic-source test but expect:

- `命中方式：语义辅助`

- [ ] **Step 2: Run the tests to verify RED**

Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: FAIL because the current page still renders `来自搜索 · ...` and `命中上下文`.

- [ ] **Step 3: Implement the minimal note detail card update**

In `note_detail_page.dart`:

1. change the first line to standalone `来自搜索`
2. render `命中方式：...` only when `searchSource` exists
3. keep `查询词：...`
4. rename `命中上下文：...` to `命中说明：...`

- [ ] **Step 4: Run the note detail tests to verify GREEN**

Run: `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: PASS

### Task 3: Verification

**Files:**
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`

- [ ] **Step 1: Run both detail page test files**

Run:

- `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
- `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/secrets/presentation/secret_detail_page.dart`
- `lib/features/notes/presentation/note_detail_page.dart`
- `test/features/secrets/presentation/secret_detail_page_test.dart`
- `test/features/notes/presentation/note_detail_page_test.dart`

Expected: clean diagnostics
