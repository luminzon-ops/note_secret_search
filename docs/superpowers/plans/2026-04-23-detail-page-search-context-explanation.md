# Detail Page Search Context Explanation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户从 SearchPage 进入 secret / note 详情页时，能立刻知道为什么来到这里，以及优先该看哪块内容。

**Architecture:** 保留现有 handoff 卡的 `命中方式 / 查询词 / 命中说明` 结构，在 detail page 内根据 `searchContext` 解析出目标字段，额外生成一条 `优先查看` 说明。解析逻辑保持在各 detail page 内部私有 helper 中，避免过度抽象。

**Tech Stack:** Flutter, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-detail-page-search-context-explanation-design.md`
- Create: `docs/superpowers/plans/2026-04-23-detail-page-search-context-explanation.md`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`

### Task 1: Add failing tests for structured detail-page search explanation

**Files:**
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`

- [ ] **Step 1: Write failing Secret detail tests**

Add tests for:

1. `标题：...` -> `优先查看：标题，这是当前最直接的命中位置。`
2. `备注：...` -> `优先查看：备注字段，查看补充说明是否匹配查询意图。`

- [ ] **Step 2: Write failing Note detail tests**

Add tests for:

1. `摘要：...` -> `优先查看：摘要，先确认概要是否对应本次查询。`
2. `正文：...` -> `优先查看：正文内容，这里最可能包含本次命中上下文。`
3. unknown context -> no `优先查看`

- [ ] **Step 3: Run detail-page tests to verify RED**

Run:

- `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
- `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: FAIL because `优先查看` is not rendered yet.

### Task 2: Implement structured handoff explanation

**Files:**
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Add minimal private helper for Secret detail**

Implement a private helper that maps `searchContext` prefixes to a `优先查看` sentence.

- [ ] **Step 2: Add minimal private helper for Note detail**

Implement a similar helper for note-specific fields.

- [ ] **Step 3: Render `优先查看` line in handoff card when available**

Insert the line after `命中说明` in both detail pages.

- [ ] **Step 4: Re-run detail-page tests to verify GREEN**

Run:

- `flutter test test/features/secrets/presentation/secret_detail_page_test.dart`
- `flutter test test/features/notes/presentation/note_detail_page_test.dart`

Expected: PASS

### Task 3: Final verification

**Files:**
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`

- [ ] **Step 1: Run detail-page tests**

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
