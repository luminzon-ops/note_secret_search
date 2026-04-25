# Semantic-Only Filter Reason Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 SearchPage 顶部观测摘要中解释 semantic-only 结果被过滤的总体原因。

**Architecture:** 保持 filtering 逻辑不变，只在 `search_result_explanation.dart` 中基于现有 filtering breakdown 派生一条总括性原因说明，并在 `search_page.dart` 的 expanded observability 区块渲染。继续保持 presentation-only 实现。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-25-semantic-only-filter-reason-design.md`
- Create: `docs/superpowers/plans/2026-04-25-semantic-only-filter-reason.md`
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

### Task 1: Add failing helper test for filter reason copy

**Files:**
- Modify: `test/features/search/presentation/search_result_explanation_test.dart`

- [ ] **Step 1: Write the failing helper test**

Given filtering stats exist, assert a new summary field contains:

- `过滤原因：被过滤的 semantic-only 结果主要来自辅助字段，且分数未达到高分保留线。`

- [ ] **Step 2: Run the targeted helper test to verify RED**

### Task 2: Render filter reason in SearchPage observability block

**Files:**
- Modify: `lib/features/search/presentation/search_result_explanation.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing widget test**

Render SearchPage with semantic-only filtering stats and expect the reason text in expanded observability.

- [ ] **Step 2: Run the widget test to verify RED**

- [ ] **Step 3: Implement minimal helper + UI render**

- [ ] **Step 4: Re-run targeted tests to verify GREEN**

### Task 3: Final verification

**Files:**
- Modify changed presentation files

- [ ] **Step 1: Run explanation helper tests**
- [ ] **Step 2: Run SearchPage tests**
- [ ] **Step 3: Run analyze**
