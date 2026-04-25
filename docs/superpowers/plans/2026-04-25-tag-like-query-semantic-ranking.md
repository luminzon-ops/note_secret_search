# Tag-Like Query Semantic Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 tag-like query 下的 semantic candidate 更偏向 `tags` 命中，而不是总被静态高质量字段压制。

**Architecture:** 保持 `SemanticSearchService` 当前质量门槛、query-aware url/username 优先级与 Top-K 策略不变，只在 query-aware priority 层新增 tag-like query -> `tags` 的最小偏置。排序仍然保持 query-aware priority -> field quality tier -> score。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-25-tag-like-query-semantic-ranking-design.md`
- Create: `docs/superpowers/plans/2026-04-25-tag-like-query-semantic-ranking.md`
- Modify: `lib/features/search/application/semantic_search_service.dart`
- Modify: `test/features/search/application/semantic_search_service_test.dart`

### Task 1: Add failing tag-like query tests

**Files:**
- Modify: `test/features/search/application/semantic_search_service_test.dart`

- [ ] **Step 1: Write the failing test for tag-like query preferring tags hits**

Add a test where:

1. one candidate is a `tags` semantic hit
2. one candidate is a stronger static-quality `summary` semantic hit
3. query is a short single-token tag-like string such as `backup`

Assert the `tags` hit is ranked first.

- [ ] **Step 2: Run the targeted test to verify RED**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart --plain-name "SemanticSearchService prefers tags semantic hits for tag-like queries"`

Expected: FAIL because current implementation only prioritizes `url` and `username`.

- [ ] **Step 3: Write the guardrail test for non-tag-like query not boosting tags**

Use a spaced query like `backup steps` and assert the stronger static-quality `summary` hit still ranks before the `tags` hit.

- [ ] **Step 4: Run the guardrail test**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart --plain-name "SemanticSearchService does not boost tags for non-tag-like queries"`

Expected: PASS or FAIL explicitly, but keep it as a regression guardrail.

### Task 2: Implement minimal tag-like query aware priority

**Files:**
- Modify: `lib/features/search/application/semantic_search_service.dart`

- [ ] **Step 1: Add tag-like query detection helper**

Implement a conservative private helper for short single-token tag-like queries.

- [ ] **Step 2: Extend query-aware field priority**

Map tag-like query -> `SemanticHitField.tags` gets query-aware priority.

- [ ] **Step 3: Re-run the targeted tests to verify GREEN**

Run both tests from Task 1.

Expected: PASS

### Task 3: Final verification

**Files:**
- Modify: `lib/features/search/application/semantic_search_service.dart`
- Modify: `test/features/search/application/semantic_search_service_test.dart`

- [ ] **Step 1: Run semantic search service tests**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/application/semantic_search_service.dart`
- `test/features/search/application/semantic_search_service_test.dart`

Expected: clean diagnostics
