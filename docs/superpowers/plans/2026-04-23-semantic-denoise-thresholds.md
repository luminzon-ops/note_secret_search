# Semantic Denoise Thresholds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收紧 placeholder semantic matching 的质量门槛，减少弱辅助字段结果进入 unified result。

**Architecture:** 保持现有 semantic search 流程不变，仅调整 `SemanticQualityPolicy.minimumThresholdFor(...)` 的字段门槛。测试集中在 policy 层，避免过度改动 service 测试基建。

**Tech Stack:** Flutter / Dart test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-semantic-denoise-thresholds-design.md`
- Create: `docs/superpowers/plans/2026-04-23-semantic-denoise-thresholds.md`
- Modify: `lib/features/search/application/semantic_quality_policy.dart`
- Create or Modify: `test/features/search/application/semantic_quality_policy_test.dart`

### Task 1: Add failing threshold tests

**Files:**
- Create or Modify: `test/features/search/application/semantic_quality_policy_test.dart`
- Modify: `lib/features/search/application/semantic_quality_policy.dart`

- [ ] **Step 1: Write failing tests for new field thresholds**

Cover:

1. title -> 0.82
2. username / summary -> 0.84
3. url / secretNote -> 0.87
4. tags / noteBody -> 0.90

- [ ] **Step 2: Run the policy tests to verify RED**

Run: `flutter test test/features/search/application/semantic_quality_policy_test.dart`

Expected: FAIL because current thresholds are still 0.82 / 0.83 / 0.85 / 0.87.

### Task 2: Implement stricter thresholds

**Files:**
- Modify: `lib/features/search/application/semantic_quality_policy.dart`

- [ ] **Step 1: Update threshold mapping**

Adjust the field-specific offsets so the effective thresholds become:

- title -> 0.82
- username / summary -> 0.84
- url / secretNote -> 0.87
- tags / noteBody -> 0.90

- [ ] **Step 2: Re-run the policy tests to verify GREEN**

Run: `flutter test test/features/search/application/semantic_quality_policy_test.dart`

Expected: PASS

### Task 3: Final verification

**Files:**
- Modify: `lib/features/search/application/semantic_quality_policy.dart`
- Create or Modify: `test/features/search/application/semantic_quality_policy_test.dart`

- [ ] **Step 1: Run policy tests**

Run: `flutter test test/features/search/application/semantic_quality_policy_test.dart`

Expected: PASS

- [ ] **Step 2: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/application/semantic_quality_policy.dart`
- `test/features/search/application/semantic_quality_policy_test.dart`

Expected: clean diagnostics
