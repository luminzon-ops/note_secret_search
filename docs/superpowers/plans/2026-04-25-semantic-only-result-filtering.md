# Semantic-Only Result Filtering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 unified results 对 semantic-only 结果更保守，只展示高质量或极高分 semantic-only 项。

**Architecture:** 保持 `SemanticSearchService` 当前候选生成、query-aware 排序与 top-k 逻辑不变，只在 `SearchFusionService.fuse()` 的融合阶段增加 semantic-only 过滤。dual-hit 与 keyword-only 完全保留不动，仅对纯 semantic 结果做展示 gate。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-25-semantic-only-result-filtering-design.md`
- Create: `docs/superpowers/plans/2026-04-25-semantic-only-result-filtering.md`
- Modify: `lib/features/search/application/search_fusion_service.dart`
- Modify: `test/features/search/application/search_fusion_service_test.dart`

### Task 1: Add failing fusion tests for semantic-only filtering

**Files:**
- Modify: `test/features/search/application/search_fusion_service_test.dart`

- [ ] **Step 1: Write the failing test for filtering weak semantic-only assist results**

Add a test where semantic results contain:

1. one semantic-only assist result with score below 0.90
2. one semantic-only high-quality result with lower score

Assert the weak assist semantic-only result is absent from unified results.

- [ ] **Step 2: Run the targeted test to verify RED**

Run: `flutter test test/features/search/application/search_fusion_service_test.dart --plain-name "filters weak semantic-only assist results from unified search"`

Expected: FAIL because semantic-only assist results are currently always retained.

- [ ] **Step 3: Write the test for keeping very high-score semantic-only assist results**

Assert a semantic-only assist result with score `>= 0.90` is still kept.

- [ ] **Step 4: Write the test for dual-hit assist results not being filtered**

Assert a dual-hit assist result still survives fusion.

### Task 2: Implement minimal semantic-only filtering

**Files:**
- Modify: `lib/features/search/application/search_fusion_service.dart`

- [ ] **Step 1: Add helper to detect semantic-only results**

- [ ] **Step 2: Add helper to decide if a semantic-only result should be kept**

Keep when:

1. field is `title / username / summary`
2. OR semanticScore >= 0.90

- [ ] **Step 3: Filter fused results before final sort**

- [ ] **Step 4: Re-run targeted tests to verify GREEN**

### Task 3: Final verification

**Files:**
- Modify: `lib/features/search/application/search_fusion_service.dart`
- Modify: `test/features/search/application/search_fusion_service_test.dart`

- [ ] **Step 1: Run fusion tests**

Run: `flutter test test/features/search/application/search_fusion_service_test.dart`

Expected: PASS

- [ ] **Step 2: Run semantic search service tests**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart`

Expected: PASS

- [ ] **Step 3: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/application/search_fusion_service.dart`
- `test/features/search/application/search_fusion_service_test.dart`

Expected: clean diagnostics
