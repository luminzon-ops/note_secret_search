# Search Status Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify search status semantics across `SearchPage` and `SearchSettingsPage` so both pages present the same blocked / initial-index / refresh / failed / ready states with consistent CTA behavior.

**Architecture:** Add a small shared status-summary layer in the search feature that converts `SearchIndexStatus` plus semantic readiness into a single UI-oriented summary. Keep navigation and button side effects in the pages, but route both pages through the same summary model so wording and action priority stay aligned without changing search ranking, indexing internals, or page structure beyond the status cards.

**Tech Stack:** Flutter, Riverpod, GoRouter, flutter_test

---

## File Map

- Create: `lib/features/search/presentation/search_status_summary.dart`
  - Shared enum / model / helper for UI-facing search status semantics.
- Modify: `lib/features/search/presentation/search_page.dart`
  - Replace split status logic with one aligned summary card and keep existing search results sections.
- Modify: `lib/features/search/presentation/search_settings_page.dart`
  - Reuse the aligned status summary for readiness + index state while preserving detail blocks.
- Modify: `test/features/search/presentation/search_page_test.dart`
  - Add widget tests for blocked / needsInitialIndex / needsRefresh / lastRunFailed / ready states.
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
  - Add widget tests for the same aligned states and CTA expectations.

---

### Task 1: Add shared search status summary model

**Files:**
- Create: `lib/features/search/presentation/search_status_summary.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing test for blocked-state wording on SearchPage**

Add a new widget test near the existing `SearchPage` status tests:

```dart
testWidgets('SearchPage shows aligned blocked status and model-management action', (
  tester,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SearchPage()),
      GoRoute(path: '/models', builder: (context, state) => const Scaffold(body: Text('models page'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(ready: false, reason: '缺少可用 embedding 模型'),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => const SearchIndexStatus(
            engineReady: false,
            engineReason: '索引引擎未就绪',
            hasActiveEmbeddingModel: false,
            pendingItems: <SearchIndexPendingItem>[],
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('本地语义链路未就绪'), findsOneWidget);
  expect(find.text('缺少可用 embedding 模型'), findsOneWidget);
  expect(find.text('前往模型管理'), findsOneWidget);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows aligned blocked status and model-management action"
```

Expected: FAIL because the current page still renders the older readiness/index wording and does not expose the exact aligned status text.

- [ ] **Step 3: Write the shared status-summary model**

Create `lib/features/search/presentation/search_status_summary.dart`:

```dart
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';

enum SearchStatusPhase { blocked, needsInitialIndex, needsRefresh, lastRunFailed, ready }

enum SearchStatusPrimaryAction { openModelManagement, triggerIndex, none }

class SearchStatusSummary {
  const SearchStatusSummary({
    required this.phase,
    required this.headline,
    required this.description,
    required this.pendingCount,
    required this.lastResultSummary,
    required this.errorText,
    required this.primaryActionLabel,
    required this.primaryAction,
  });

  final SearchStatusPhase phase;
  final String headline;
  final String description;
  final int pendingCount;
  final String? lastResultSummary;
  final String? errorText;
  final String? primaryActionLabel;
  final SearchStatusPrimaryAction primaryAction;
}

SearchStatusSummary buildSearchStatusSummary({
  required SemanticSearchReadiness readiness,
  required SearchIndexStatus status,
}) {
  final lastSummary = _lastResultSummary(status.taskState);

  if (!status.readyForIndexing) {
    return SearchStatusSummary(
      phase: SearchStatusPhase.blocked,
      headline: '本地语义链路未就绪',
      description: readiness.reason,
      pendingCount: status.pendingItems.length,
      lastResultSummary: lastSummary,
      errorText: status.taskState.lastError,
      primaryActionLabel: '前往模型管理',
      primaryAction: SearchStatusPrimaryAction.openModelManagement,
    );
  }

  if (status.taskState.lastError != null) {
    return SearchStatusSummary(
      phase: SearchStatusPhase.lastRunFailed,
      headline: '最近一次索引失败',
      description: '索引任务未成功完成，建议先重试索引再判断语义检索效果。',
      pendingCount: status.pendingItems.length,
      lastResultSummary: lastSummary,
      errorText: status.taskState.lastError,
      primaryActionLabel: '重试索引',
      primaryAction: SearchStatusPrimaryAction.triggerIndex,
    );
  }

  if (status.pendingItems.isNotEmpty && status.taskState.lastCompletedAt == null) {
    return SearchStatusSummary(
      phase: SearchStatusPhase.needsInitialIndex,
      headline: '建议先构建本地索引',
      description: '已有待索引内容，完成首次构建后再查看语义检索结果会更稳定。',
      pendingCount: status.pendingItems.length,
      lastResultSummary: lastSummary,
      errorText: null,
      primaryActionLabel: '立即构建索引',
      primaryAction: SearchStatusPrimaryAction.triggerIndex,
    );
  }

  if (status.pendingItems.isNotEmpty) {
    return SearchStatusSummary(
      phase: SearchStatusPhase.needsRefresh,
      headline: '索引需要刷新',
      description: '索引已有新变更，建议刷新后再判断当前语义检索结果。',
      pendingCount: status.pendingItems.length,
      lastResultSummary: lastSummary,
      errorText: null,
      primaryActionLabel: '刷新索引',
      primaryAction: SearchStatusPrimaryAction.triggerIndex,
    );
  }

  return SearchStatusSummary(
    phase: SearchStatusPhase.ready,
    headline: '本地语义检索已可用',
    description: '当前索引已最新，可以直接继续检索。',
    pendingCount: 0,
    lastResultSummary: lastSummary,
    errorText: null,
    primaryActionLabel: null,
    primaryAction: SearchStatusPrimaryAction.none,
  );
}

String? _lastResultSummary(SearchIndexTaskState taskState) {
  if (taskState.lastCompletedAt == null) {
    return null;
  }
  if (taskState.lastError != null) {
    return '最近一次完成 0 项，仍有错误需要处理。';
  }
  return '最近一次完成 ${taskState.lastIndexedCount} 项，当前无错误。';
}
```

- [ ] **Step 4: Run the test to verify the model alone is not yet enough**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows aligned blocked status and model-management action"
```

Expected: FAIL, but now because `SearchPage` has not been switched to the new summary model yet.

- [ ] **Step 5: Commit the shared model**

```powershell
git add "lib/features/search/presentation/search_status_summary.dart" "test/features/search/presentation/search_page_test.dart"
git commit -m "feat: add shared search status summary model"
```

---

### Task 2: Align SearchPage status card behavior

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write failing SearchPage tests for the remaining aligned states**

Add four widget tests to `test/features/search/presentation/search_page_test.dart`:

```dart
testWidgets('SearchPage shows initial-index action when first build is required', (tester) async {
  // overrides: readiness ready, lastCompletedAt null, pendingItems non-empty
  expect(find.text('建议先构建本地索引'), findsOneWidget);
  expect(find.text('立即构建索引'), findsOneWidget);
});

testWidgets('SearchPage shows refresh action when index has pending changes', (tester) async {
  // overrides: readiness ready, lastCompletedAt set, pendingItems non-empty
  expect(find.text('索引需要刷新'), findsOneWidget);
  expect(find.text('刷新索引'), findsOneWidget);
});

testWidgets('SearchPage shows failure action when last index run failed', (tester) async {
  // overrides: readiness ready, taskState.lastError set
  expect(find.text('最近一次索引失败'), findsOneWidget);
  expect(find.text('重试索引'), findsOneWidget);
  expect(find.text('disk full'), findsOneWidget);
});

testWidgets('SearchPage shows ready state without stale build prompt', (tester) async {
  // overrides: readiness ready, pendingItems empty, no error, lastCompletedAt set
  expect(find.text('本地语义检索已可用'), findsOneWidget);
  expect(find.text('当前索引已最新，可以直接继续检索。'), findsOneWidget);
  expect(find.text('立即构建索引'), findsNothing);
  expect(find.text('刷新索引'), findsNothing);
});
```

- [ ] **Step 2: Run the SearchPage status subset to verify failure**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart
```

Expected: FAIL on the newly-added aligned-state assertions.

- [ ] **Step 3: Replace split SearchPage status logic with the shared summary**

Update the imports and status section in `lib/features/search/presentation/search_page.dart`:

```dart
import 'package:note_secret_search/features/search/presentation/search_status_summary.dart';
```

Replace the two-card status area with a single summary-driven widget:

```dart
readinessAsync.when(
  data: (readiness) => indexStatusAsync.when(
    data: (status) => _SearchStatusCard(
      summary: buildSearchStatusSummary(readiness: readiness, status: status),
    ),
    loading: () => const SizedBox.shrink(),
    error: (error, stackTrace) => Text(error.toString()),
  ),
  loading: () => const SizedBox.shrink(),
  error: (error, stackTrace) => Text(error.toString()),
),
```

Add a new `ConsumerWidget` to the file:

```dart
class _SearchStatusCard extends ConsumerWidget {
  const _SearchStatusCard({required this.summary});

  final SearchStatusSummary summary;

  Future<void> _triggerIndex(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(searchIndexControllerProvider).indexPending();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始构建索引，请稍后刷新搜索结果。')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('索引触发失败，请稍后重试。')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.headline, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(summary.description),
            if (summary.pendingCount > 0) ...[
              const SizedBox(height: 8),
              Text('待索引内容：${summary.pendingCount} 项'),
            ],
            if (summary.lastResultSummary != null) ...[
              const SizedBox(height: 8),
              Text(summary.lastResultSummary!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (summary.errorText != null) ...[
              const SizedBox(height: 8),
              Text(summary.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (summary.primaryAction != SearchStatusPrimaryAction.none && summary.primaryActionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () {
                  switch (summary.primaryAction) {
                    case SearchStatusPrimaryAction.openModelManagement:
                      context.push('/models');
                      break;
                    case SearchStatusPrimaryAction.triggerIndex:
                      _triggerIndex(context, ref);
                      break;
                    case SearchStatusPrimaryAction.none:
                      break;
                  }
                },
                icon: const Icon(Icons.chevron_right),
                label: Text(summary.primaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

Delete the old `_SemanticPipelineStatusCard` and `_SearchIndexHintCard` classes after the new widget is wired in.

- [ ] **Step 4: Run SearchPage tests to verify they pass**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the SearchPage alignment**

```powershell
git add "lib/features/search/presentation/search_page.dart" "test/features/search/presentation/search_page_test.dart"
git commit -m "feat: align search page status semantics"
```

---

### Task 3: Align SearchSettingsPage headline / CTA semantics

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Test: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Write failing SearchSettingsPage tests for aligned phases**

Add tests to `test/features/search/presentation/search_settings_page_test.dart`:

```dart
testWidgets('SearchSettingsPage shows aligned initial-index status and trigger action', (tester) async {
  // readyForIndexing true, lastCompletedAt null, pendingItems non-empty
  expect(find.text('建议先构建本地索引'), findsOneWidget);
  expect(find.text('立即构建索引'), findsOneWidget);
});

testWidgets('SearchSettingsPage shows aligned refresh status and action', (tester) async {
  // readyForIndexing true, lastCompletedAt set, pendingItems non-empty
  expect(find.text('索引需要刷新'), findsOneWidget);
  expect(find.text('刷新索引'), findsOneWidget);
});

testWidgets('SearchSettingsPage shows aligned failure status and retry action', (tester) async {
  // taskState.lastError set
  expect(find.text('最近一次索引失败'), findsOneWidget);
  expect(find.text('重试索引'), findsOneWidget);
});

testWidgets('SearchSettingsPage shows aligned ready state without build prompt', (tester) async {
  // pending empty, lastCompletedAt set, no error
  expect(find.text('本地语义检索已可用'), findsOneWidget);
  expect(find.text('当前索引已最新，可以直接继续检索。'), findsOneWidget);
  expect(find.text('构建占位索引'), findsNothing);
});
```

- [ ] **Step 2: Run the SearchSettingsPage test file to verify failure**

Run:

```powershell
flutter test test/features/search/presentation/search_settings_page_test.dart
```

Expected: FAIL on the new aligned-state assertions.

- [ ] **Step 3: Update SearchSettingsPage to consume the shared summary**

Import the shared summary file:

```dart
import 'package:note_secret_search/features/search/presentation/search_status_summary.dart';
```

Inside `build`, construct the summary only when both readiness and status are available:

```dart
final alignedSummary =
    semanticReadinessAsync.hasValue && indexStatusAsync.hasValue
        ? buildSearchStatusSummary(
            readiness: semanticReadinessAsync.requireValue,
            status: indexStatusAsync.requireValue,
          )
        : null;
```

Pass `alignedSummary` into `_SemanticReadinessCard` and `_IndexStatusCard`.

Update `_SemanticReadinessCard` signature:

```dart
const _SemanticReadinessCard({
  required this.readiness,
  required this.scope,
  required this.indexStatus,
  required this.summary,
});

final SearchStatusSummary summary;
```

Use aligned wording in the top block:

```dart
Text(summary.headline, style: Theme.of(context).textTheme.titleMedium),
const SizedBox(height: 8),
Text(summary.description),
```

Update `_IndexStatusCard` signature:

```dart
const _IndexStatusCard({required this.status, required this.summary});

final SearchStatusSummary summary;
```

Replace `_progressSummary(status)` usage with summary-driven text:

```dart
Text(
  '当前状态：${summary.headline}',
  style: Theme.of(context).textTheme.labelLarge,
),
const SizedBox(height: 4),
Text(summary.description),
```

Replace the bottom action button label selection with summary-driven CTA:

```dart
if (summary.primaryAction == SearchStatusPrimaryAction.triggerIndex && summary.primaryActionLabel != null) ...[
  const SizedBox(height: 12),
  FilledButton.tonalIcon(
    onPressed: () => _handleIndexAction(context, ref),
    icon: const Icon(Icons.auto_fix_high_outlined),
    label: Text(summary.primaryActionLabel!),
  ),
]
```

When `summary.phase == SearchStatusPhase.ready`, show a positive ready note in place of the old “无需手动触发构建” copy:

```dart
const SizedBox(height: 12),
const Text('当前索引已最新，可以直接继续使用语义检索。'),
```

- [ ] **Step 4: Run SearchSettingsPage tests to verify they pass**

Run:

```powershell
flutter test test/features/search/presentation/search_settings_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the SearchSettingsPage alignment**

```powershell
git add "lib/features/search/presentation/search_settings_page.dart" "test/features/search/presentation/search_settings_page_test.dart"
git commit -m "feat: align search settings status semantics"
```

---

### Task 4: Run final verification and clean diagnostics

**Files:**
- Modify: `lib/features/search/presentation/search_status_summary.dart` (if needed)
- Modify: `lib/features/search/presentation/search_page.dart` (if needed)
- Modify: `lib/features/search/presentation/search_settings_page.dart` (if needed)
- Test: `test/features/search/presentation/search_page_test.dart`
- Test: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Run the focused search presentation tests together**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart; if ($?) { flutter test test/features/search/presentation/search_settings_page_test.dart }
```

Expected: both test files PASS.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run LSP diagnostics on changed files**

Check these files:

```text
lib/features/search/presentation/search_status_summary.dart
lib/features/search/presentation/search_page.dart
lib/features/search/presentation/search_settings_page.dart
```

Expected: clean diagnostics or only pre-existing unrelated issues. Fix any new issues before finishing.

- [ ] **Step 4: If verification fails, make the minimal fix and re-run only the failing command**

Use this rule:

```text
If a widget test fails, fix the smallest UI or expectation mismatch and rerun that specific test file first.
If analyze fails, fix only the reported issue and rerun flutter analyze.
If diagnostics fail on a changed file, fix the exact diagnostic and rerun diagnostics on that file.
```

- [ ] **Step 5: Commit the verified feature slice**

```powershell
git add "lib/features/search/presentation/search_status_summary.dart" "lib/features/search/presentation/search_page.dart" "lib/features/search/presentation/search_settings_page.dart" "test/features/search/presentation/search_page_test.dart" "test/features/search/presentation/search_settings_page_test.dart"
git commit -m "feat: align search status messaging across pages"
```

---

## Self-Review

- Spec coverage:
  - Shared state model: Task 1
  - SearchPage aligned status card: Task 2
  - SearchSettingsPage aligned semantics with detailed status retained: Task 3
  - Widget-test coverage for blocked / needsInitialIndex / needsRefresh / lastRunFailed / ready: Tasks 2 and 3
  - Verification: Task 4
- Placeholder scan: no `TODO`, `TBD`, or abstract “write tests” placeholders remain.
- Type consistency: `SearchStatusSummary`, `SearchStatusPhase`, and `SearchStatusPrimaryAction` are defined once in the shared file and reused consistently in later tasks.
