# Search Fusion Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 unified search 排序更可靠地体现双命中与高质量语义字段的结果质量。

**Architecture:** 修改 `SearchFusionService` 的排序比较逻辑，在来源优先级之后引入语义质量层级，再使用 semantic score 与字段优先级做细化排序。保持 provider 层不变，测试集中在 fusion service 上。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-search-fusion-ranking-design.md`
- Create: `docs/superpowers/plans/2026-04-23-search-fusion-ranking.md`
- Modify: `lib/features/search/application/search_fusion_service.dart`
- Create or Modify: `test/features/search/application/search_fusion_service_test.dart`

### Task 1: Add failing ranking tests for SearchFusionService

**Files:**
- Create or Modify: `test/features/search/application/search_fusion_service_test.dart`
- Modify: `lib/features/search/application/search_fusion_service.dart`

- [ ] **Step 1: Write failing ranking tests**

Cover at least:

1. dual-hit + title beats semantic-only + tags even when semantic-only has a higher score
2. semantic-only + title beats semantic-only + noteBody
3. dual-hit + assist beats keyword-only
4. same quality tier still uses higher semantic score first

- [ ] **Step 2: Run the fusion service tests to verify RED**

Run: `flutter test test/features/search/application/search_fusion_service_test.dart`

Expected: FAIL because current ranking does not fully respect the new quality ordering.

### Task 2: Implement minimal ranking improvement

**Files:**
- Modify: `lib/features/search/application/search_fusion_service.dart`

- [ ] **Step 1: Add semantic quality tier helper**

Create a helper that groups semantic fields into:

- high-quality
- assist
- none

- [ ] **Step 2: Update sort comparator**

Sort using:

1. source priority
2. semantic quality tier
3. semantic score
4. semantic field priority
5. favorite
6. updatedAt

- [ ] **Step 3: Re-run fusion service tests to verify GREEN**

Run: `flutter test test/features/search/application/search_fusion_service_test.dart`

Expected: PASS

### Task 3: Final verification

**Files:**
- Modify: `lib/features/search/application/search_fusion_service.dart`
- Create or Modify: `test/features/search/application/search_fusion_service_test.dart`

- [ ] **Step 1: Run fusion service tests**

Run: `flutter test test/features/search/application/search_fusion_service_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/application/search_fusion_service.dart`
- `test/features/search/application/search_fusion_service_test.dart`

Expected: clean diagnostics
