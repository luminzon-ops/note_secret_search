# Query-Aware Semantic Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 semantic candidate 排序在 URL-like 与 account-like query 下更贴近用户意图。

**Architecture:** 保持 `SemanticSearchService` 当前质量门槛、分片聚合与 Top-K 策略不变，只在 `search()` 的 candidate 排序阶段增加 query-aware 意图优先级。先看 query 是否像 URL 或账号，再决定是否给 `url` / `username` 命中更高优先级，最后仍回落到字段质量层级与 score。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-25-query-aware-semantic-ranking-design.md`
- Create: `docs/superpowers/plans/2026-04-25-query-aware-semantic-ranking.md`
- Modify: `lib/features/search/application/semantic_search_service.dart`
- Modify: `test/features/search/application/semantic_search_service_test.dart`

### Task 1: Add failing query-aware ranking tests

**Files:**
- Modify: `test/features/search/application/semantic_search_service_test.dart`

- [ ] **Step 1: Write the failing test for URL-like query preferring url hits**

Add a test where:

1. one candidate is a `url` semantic hit
2. one candidate is a stronger static-quality `summary` semantic hit
3. query looks like a URL or domain

Assert the `url` hit is ranked first.

- [ ] **Step 2: Run the targeted test to verify RED**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart --plain-name "SemanticSearchService prefers url semantic hits for URL-like queries"`

Expected: FAIL because current implementation only knows field quality + score.

- [ ] **Step 3: Write the failing test for account-like query preferring username hits**

Add a test where:

1. one candidate is a `username` semantic hit
2. one candidate is a stronger static-quality `summary` semantic hit
3. query contains `@`

Assert the `username` hit is ranked first.

- [ ] **Step 4: Run the targeted test to verify RED**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart --plain-name "SemanticSearchService prefers username semantic hits for account-like queries"`

Expected: FAIL because current implementation does not inspect query intent.

### Task 2: Implement minimal query-aware semantic ranking

**Files:**
- Modify: `lib/features/search/application/semantic_search_service.dart`

- [ ] **Step 1: Add query-intent helpers**

Add minimal private helpers to detect:

1. URL-like query
2. account-like query

- [ ] **Step 2: Add query-aware field priority helper**

Map:

- URL-like query -> `url` field gets highest query-aware priority
- account-like query -> `username` field gets highest query-aware priority
- otherwise -> no extra priority

- [ ] **Step 3: Update candidate sorting**

Sort by:

1. query-aware priority descending
2. field quality tier descending
3. score descending

- [ ] **Step 4: Re-run targeted tests to verify GREEN**

Run both targeted tests from Task 1.

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
