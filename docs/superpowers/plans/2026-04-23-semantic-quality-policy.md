# Semantic Quality Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将语义质量门槛从 `SemanticSearchService` 内的硬编码提升为集中策略对象，并让 SearchPage 顶部链路说明同步补充质量门控文案。

**Architecture:** 新增一个 `semantic_quality_policy.dart` 作为默认保守 MVP 策略的集中定义点，负责全局最低门槛、字段级门槛和 UI 说明文案。`SemanticSearchService` 改为依赖该策略对象做质量过滤，`SearchPage` 在语义信号参与结果时补一句“仅展示通过最低质量门槛的命中”。

**Tech Stack:** Flutter, Riverpod, flutter_test

---

## File Structure

- Create: `docs/superpowers/specs/2026-04-23-semantic-quality-policy-design.md`
  - 语义质量策略设计文档
- Create: `docs/superpowers/plans/2026-04-23-semantic-quality-policy.md`
  - 本实现计划
- Create: `lib/features/search/application/semantic_quality_policy.dart`
  - 集中定义默认保守语义质量策略
- Modify: `lib/features/search/application/semantic_search_service.dart`
  - 从硬编码阈值迁移到策略对象
- Modify: `lib/features/search/presentation/search_page.dart`
  - 顶部链路说明补充质量门控文案
- Modify: `test/features/search/application/semantic_search_service_test.dart`
  - 增加策略对象相关测试
- Modify: `test/features/search/presentation/search_page_test.dart`
  - 增加搜索页顶部说明文案测试

### Task 1: Extract semantic quality policy

**Files:**
- Create: `lib/features/search/application/semantic_quality_policy.dart`
- Modify: `test/features/search/application/semantic_search_service_test.dart`

- [ ] **Step 1: Write the failing test for the default policy thresholds**

Add a unit test that expects the default conservative policy to return:

- `title` threshold lower than `noteBody`
- `tags` threshold equal to or stricter than `noteBody`

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart --plain-name "Semantic quality policy uses stricter thresholds for weaker fields"`

Expected: FAIL because the policy object does not exist yet.

- [ ] **Step 3: Add the minimal policy object**

Create `semantic_quality_policy.dart` with a default policy, for example:

```dart
class SemanticQualityPolicy {
  const SemanticQualityPolicy({required this.minimumSemanticScore});

  const SemanticQualityPolicy.conservativeMvp() : minimumSemanticScore = 0.82;

  final double minimumSemanticScore;

  double minimumThresholdFor(SemanticHitField field) { ... }

  String get searchPageQualityHint => '当前语义结果仅展示通过最低质量门槛的命中。';
}
```

- [ ] **Step 4: Run the policy test to verify GREEN**

Run the test from Step 2.

Expected: PASS

### Task 2: Move SemanticSearchService to the policy object

**Files:**
- Modify: `lib/features/search/application/semantic_search_service.dart`
- Modify: `test/features/search/application/semantic_search_service_test.dart`

- [ ] **Step 1: Keep the existing quality-gate tests and add the new policy test**

The file should now cover:

1. strong title hit kept
2. weak tags hit filtered
3. note body stricter than title
4. policy thresholds differ by field

- [ ] **Step 2: Run the full semantic service test file to verify RED or preserve GREEN**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart`

Expected: may PASS if behavior is preserved, or FAIL while refactor is incomplete.

- [ ] **Step 3: Refactor the service to depend on the policy**

Inject the policy into `SemanticSearchService` with a default conservative value.

Expected pattern:

```dart
const SemanticSearchService({
  required SearchRepository repository,
  required EmbeddingEngine embeddingEngine,
  required CryptoService cryptoService,
  SemanticQualityPolicy qualityPolicy = const SemanticQualityPolicy.conservativeMvp(),
})
```

Then replace the private threshold helpers with `qualityPolicy.minimumThresholdFor(field)`.

- [ ] **Step 4: Run the semantic service tests to verify GREEN**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart`

Expected: PASS

### Task 3: Tighten SearchPage explanation copy

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing test for the new quality hint when semantic results participate**

Add a widget test that expects the search page to show:

- `当前语义结果仅展示通过最低质量门槛的命中。`

when semantic signals participate in unified results.

- [ ] **Step 2: Run the test to verify RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows semantic quality gate hint when semantic signals participate in unified results"`

Expected: FAIL because the new hint is not rendered yet.

- [ ] **Step 3: Update the top summary copy minimally**

Add the new quality hint only in the semantic-participating branch of `SearchPage`'s top pipeline summary.

- [ ] **Step 4: Run the targeted test to verify GREEN**

Run the test from Step 2.

Expected: PASS

### Task 4: Verification

**Files:**
- Create: `lib/features/search/application/semantic_quality_policy.dart`
- Modify: `lib/features/search/application/semantic_search_service.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `test/features/search/application/semantic_search_service_test.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Run semantic service tests**

Run: `flutter test test/features/search/application/semantic_search_service_test.dart`

Expected: PASS

- [ ] **Step 2: Run SearchPage tests**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS

- [ ] **Step 3: Run analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Check diagnostics on changed files**

Run LSP diagnostics on:

- `lib/features/search/application/semantic_quality_policy.dart`
- `lib/features/search/application/semantic_search_service.dart`
- `lib/features/search/presentation/search_page.dart`
- `test/features/search/application/semantic_search_service_test.dart`
- `test/features/search/presentation/search_page_test.dart`

Expected: clean diagnostics
