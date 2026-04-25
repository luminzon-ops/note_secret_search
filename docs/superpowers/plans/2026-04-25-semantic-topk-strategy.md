# Semantic Top-K Strategy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化 semantic candidate 的 Top-K 截断，让高价值语义字段命中优先保留，再由辅助语义命中回填。

**Architecture:** 保持 `SemanticSearchService` 的查询、分片聚合与质量门槛逻辑不变，只调整 `search()` 中对候选列表的排序方式。先按语义字段质量层级排序，再按 score 排序，最后做 `take(5)`，从而让 Top-K 更贴近用户真正想看的强语义候选。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-25-semantic-topk-strategy-design.md`
- Create: `docs/superpowers/plans/2026-04-25-semantic-topk-strategy.md`
- Modify: `lib/features/search/application/semantic_search_service.dart`
- Modify: `test/features/search/application/semantic_search_service_test.dart`

### Task 1: Add failing semantic Top-K tests

**Files:**
- Modify: `test/features/search/application/semantic_search_service_test.dart`

- [ ] **Step 1: Write the failing test for high-quality semantic hits surviving Top-K trimming**

Add a test with more than 5 semantic candidates where assist-field hits have slightly higher scores than a title/summary hit, and assert the final top 5 still keeps the high-quality field hit.

- [ ] **Step 2: Run the targeted test to verify RED**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart --plain-name "SemanticSearchService keeps high-quality field hits inside semantic top-k before lower-priority fields"`

Expected: FAIL because current implementation sorts only by score before `take(5)`.

- [ ] **Step 3: Write the failing test for assist fallback when high-quality hits are insufficient**

Add a test where only one high-quality hit exists and the remaining top-k slots are filled by assist-field hits.

- [ ] **Step 4: Run the second targeted test to verify RED or current behavior explicitly**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart --plain-name "SemanticSearchService still backfills semantic top-k with assist fields when high-quality hits are fewer than k"`

Expected: PASS or FAIL, but keep it explicit as a guardrail.

### Task 2: Implement minimal quality-aware Top-K sorting

**Files:**
- Modify: `lib/features/search/application/semantic_search_service.dart`

- [ ] **Step 1: Add a semantic field quality tier helper**

Add a private helper that maps:

- `title / username / summary` -> high tier
- `url / secretNote / tags / noteBody` -> assist tier

- [ ] **Step 2: Use the helper in candidate sorting before `take(5)`**

Sort semantic candidates by:

1. field quality tier descending
2. score descending

- [ ] **Step 3: Re-run targeted tests to verify GREEN**

Run the two targeted semantic search tests from Task 1.

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
