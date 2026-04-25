# Detail Page Semantic-Only Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 secret / note detail page 中补充 semantic-only retained result 的统一承接说明。

**Architecture:** 保持现有 detail page 搜索 handoff card 结构不变，只在 presentation 层基于 `searchSource` 派生一条额外说明。secret / note 共用同一条承接文案，避免过早做页面分叉。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-25-detail-page-semantic-only-handoff-design.md`
- Create: `docs/superpowers/plans/2026-04-25-detail-page-semantic-only-handoff.md`
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`

### Task 1: Add failing detail page tests for semantic-only handoff copy

**Files:**
- Modify: `test/features/secrets/presentation/secret_detail_page_test.dart`
- Modify: `test/features/notes/presentation/note_detail_page_test.dart`

- [ ] **Step 1: Write the failing SecretDetailPage test**

With `searchSource: 'semantic'`, expect:

- `承接说明：该结果作为保留的语义命中进入详情页，建议结合命中字段与正文继续确认。`

- [ ] **Step 2: Run the secret detail test to verify RED**

- [ ] **Step 3: Write the failing NoteDetailPage test**

With `searchSource: 'semantic'`, expect the same handoff copy.

- [ ] **Step 4: Run the note detail test to verify RED**

### Task 2: Implement minimal semantic-only handoff copy

**Files:**
- Modify: `lib/features/secrets/presentation/secret_detail_page.dart`
- Modify: `lib/features/notes/presentation/note_detail_page.dart`

- [ ] **Step 1: Add a small helper for semantic retained handoff copy**

- [ ] **Step 2: Render the copy only for `searchSource == 'semantic'`**

- [ ] **Step 3: Re-run targeted tests to verify GREEN**

### Task 3: Final verification

**Files:**
- Modify changed detail page files and tests

- [ ] **Step 1: Run secret detail tests**
- [ ] **Step 2: Run note detail tests**
- [ ] **Step 3: Run analyze**
