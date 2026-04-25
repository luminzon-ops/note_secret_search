# Search Refresh Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared automatic refresh closure after index actions so SearchPage and SearchSettingsPage both show refresh-in-progress feedback and automatically render updated search state/results.

**Architecture:** Introduce a lightweight shared refresh-session state in the search feature and a higher-level controller method that performs indexing, enters refresh mode, invalidates search-related providers, eagerly re-reads them, and exits refresh mode. Keep existing page structure, but make both pages consume the shared refresh-session state so the button loading state and in-card refresh message stay synchronized across routes.

**Tech Stack:** Flutter, Riverpod, GoRouter, flutter_test

---

## File Map

- Modify: `lib/features/search/application/search_providers.dart`
  - Add refresh-session state and a combined `indexPendingAndRefresh()` controller flow.
- Modify: `lib/features/search/presentation/search_status_summary.dart`
  - Extend the UI summary model with refresh-session awareness if needed.
- Modify: `lib/features/search/presentation/search_page.dart`
  - Show shared refresh-state loading on the action button and a refresh-in-progress hint in the status card.
- Modify: `lib/features/search/presentation/search_settings_page.dart`
  - Mirror the same refresh-state loading and refresh-in-progress hint.
- Modify: `test/features/search/presentation/search_page_test.dart`
  - Add widget tests for SearchPage refresh closure behavior.
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
  - Add widget tests for SearchSettingsPage refresh closure behavior.

---

### Task 1: Add shared refresh-session state and combined controller flow

**Files:**
- Modify: `lib/features/search/application/search_providers.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing SearchPage test for refresh-in-progress UI state**

Add this widget test to `test/features/search/presentation/search_page_test.dart` near the index-action tests:

```dart
testWidgets('SearchPage shows refresh-in-progress hint and disables action while shared refresh session is active', (
  tester,
) async {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: [
              SearchIndexPendingItem(
                sourceId: 'secret-1',
                sourceType: SearchSourceType.secret,
                title: 'Bank Account',
                updatedAt: DateTime(2026, 1, 2),
                plainTextHash: 'hash-1',
                indexPlainText: 'Bank Account',
              ),
            ],
          ),
        ),
        searchRefreshSessionProvider.overrideWith(
          (ref) => const SearchRefreshSessionState(
            refreshing: true,
            message: '正在刷新搜索状态与结果...',
          ),
        ),
        unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('正在刷新搜索状态与结果...'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsWidgets);
  final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
  expect(button.onPressed, isNull);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows refresh-in-progress hint and disables action while shared refresh session is active"
```

Expected: FAIL because the shared refresh provider does not exist yet and the page does not render the refresh hint.

- [ ] **Step 3: Add shared refresh-session state and combined controller method**

Update `lib/features/search/application/search_providers.dart` with a new state model and provider:

```dart
class SearchRefreshSessionState {
  const SearchRefreshSessionState({
    required this.refreshing,
    this.message,
    this.lastCompletedAt,
  });

  const SearchRefreshSessionState.idle()
      : refreshing = false,
        message = null,
        lastCompletedAt = null;

  final bool refreshing;
  final String? message;
  final DateTime? lastCompletedAt;

  SearchRefreshSessionState copyWith({
    bool? refreshing,
    String? message,
    bool clearMessage = false,
    DateTime? lastCompletedAt,
    bool clearLastCompletedAt = false,
  }) {
    return SearchRefreshSessionState(
      refreshing: refreshing ?? this.refreshing,
      message: clearMessage ? null : (message ?? this.message),
      lastCompletedAt: clearLastCompletedAt ? null : (lastCompletedAt ?? this.lastCompletedAt),
    );
  }
}

final searchRefreshSessionProvider = StateProvider<SearchRefreshSessionState>(
  (ref) => const SearchRefreshSessionState.idle(),
);
```

Then extend `SearchIndexController` with a new method:

```dart
Future<void> indexPendingAndRefresh() async {
  await indexPending();

  _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle().copyWith(
        refreshing: true,
        message: '正在刷新搜索状态与结果...',
      );

  try {
    _ref.invalidate(searchIndexStatusProvider);
    _ref.invalidate(semanticSearchResultsProvider);
    _ref.invalidate(unifiedSearchResultsProvider);

    await _ref.read(searchIndexStatusProvider.future);
    await _ref.read(semanticSearchResultsProvider.future);
    await _ref.read(unifiedSearchResultsProvider.future);

    _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle()
        .copyWith(lastCompletedAt: DateTime.now());
  } catch (_) {
    _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle();
    rethrow;
  }
}
```

- [ ] **Step 4: Run the SearchPage refresh-state test again**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage shows refresh-in-progress hint and disables action while shared refresh session is active"
```

Expected: still FAIL, but now because `SearchPage` does not consume the new refresh-session state yet.

- [ ] **Step 5: Commit the shared refresh-session state**

```powershell
git add "lib/features/search/application/search_providers.dart" "test/features/search/presentation/search_page_test.dart"
git commit -m "feat: add shared search refresh session state"
```

---

### Task 2: Update SearchPage to show refresh closure feedback

**Files:**
- Modify: `lib/features/search/presentation/search_page.dart`
- Modify: `lib/features/search/presentation/search_status_summary.dart`
- Test: `test/features/search/presentation/search_page_test.dart`

- [ ] **Step 1: Write the failing SearchPage test for action-triggered auto refresh**

Add this test to `test/features/search/presentation/search_page_test.dart`:

```dart
testWidgets('SearchPage index action uses combined refresh controller flow', (tester) async {
  late _RecordingSearchIndexController controller;
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => const SearchPage())],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: [
              SearchIndexPendingItem(
                sourceId: 'secret-1',
                sourceType: SearchSourceType.secret,
                title: 'Bank Account',
                updatedAt: DateTime(2026, 1, 2),
                plainTextHash: 'hash-1',
                indexPlainText: 'Bank Account',
              ),
            ],
          ),
        ),
        searchIndexControllerProvider.overrideWith((ref) {
          controller = _RecordingSearchIndexController(ref: ref);
          return controller;
        }),
        unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.text('立即构建索引'));
  await tester.pump();

  expect(controller.refreshCalls, 1);
});
```

Also extend the test double in `test/features/search/presentation/search_page_test.dart`:

```dart
class _RecordingSearchIndexController extends SearchIndexController {
  _RecordingSearchIndexController({required super.ref, this.error});

  int calls = 0;
  int refreshCalls = 0;
  final Object? error;

  @override
  Future<void> indexPending() async {
    calls++;
    if (error != null) {
      throw error!;
    }
  }

  @override
  Future<void> indexPendingAndRefresh() async {
    refreshCalls++;
    if (error != null) {
      throw error!;
    }
  }
}
```

- [ ] **Step 2: Run the SearchPage refresh-controller test to verify failure**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart --plain-name "SearchPage index action uses combined refresh controller flow"
```

Expected: FAIL because the page still calls `indexPending()` directly.

- [ ] **Step 3: Consume the refresh-session state in SearchPage**

Update `lib/features/search/presentation/search_page.dart` to watch the new provider:

```dart
final refreshSession = ref.watch(searchRefreshSessionProvider);
```

Pass it into `_SearchStatusCard`:

```dart
_SearchStatusCard(
  summary: buildSearchStatusSummary(readiness: readiness, status: status),
  refreshSession: refreshSession,
)
```

Update `_SearchStatusCard` signature:

```dart
const _SearchStatusCard({required this.summary, required this.refreshSession});

final SearchStatusSummary summary;
final SearchRefreshSessionState refreshSession;
```

Change the action handler to call the combined method:

```dart
await ref.read(searchIndexControllerProvider).indexPendingAndRefresh();
```

In the card body, show the shared refresh hint and inline loading:

```dart
if (refreshSession.refreshing && refreshSession.message != null) ...[
  const SizedBox(height: 8),
  Row(
    children: [
      const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(refreshSession.message!)),
    ],
  ),
],
```

And replace the button body:

```dart
FilledButton.tonalIcon(
  onPressed: refreshSession.refreshing
      ? null
      : () {
          switch (summary.primaryAction) {
            case SearchStatusPrimaryAction.openModelManagement:
              context.push('/models');
              break;
            case SearchStatusPrimaryAction.triggerIndex:
              _handleIndexAction(context, ref);
              break;
            case SearchStatusPrimaryAction.none:
              break;
          }
        },
  icon: refreshSession.refreshing
      ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(
          summary.primaryAction == SearchStatusPrimaryAction.openModelManagement
              ? Icons.memory_outlined
              : Icons.auto_fix_high_outlined,
        ),
  label: Text(summary.primaryActionLabel!),
)
```

- [ ] **Step 4: Run the full SearchPage test file**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the SearchPage refresh closure**

```powershell
git add "lib/features/search/presentation/search_page.dart" "lib/features/search/presentation/search_status_summary.dart" "test/features/search/presentation/search_page_test.dart"
git commit -m "feat: add refresh closure to search page"
```

---

### Task 3: Update SearchSettingsPage to mirror shared refresh closure

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Test: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Write failing SearchSettingsPage tests for shared refresh UI**

Add these tests to `test/features/search/presentation/search_settings_page_test.dart`:

```dart
testWidgets('SearchSettingsPage shows shared refresh hint and disables index actions while refresh session is active', (
  tester,
) async {
  final pendingItem = SearchIndexPendingItem(
    sourceId: 'secret-1',
    sourceType: SearchSourceType.secret,
    title: '邮箱账号',
    updatedAt: DateTime(2026, 4, 21, 10, 0),
    plainTextHash: 'hash-refresh-ui',
    indexPlainText: '邮箱账号\nuser@example.com',
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: [pendingItem],
          ),
        ),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        searchRefreshSessionProvider.overrideWith(
          (ref) => const SearchRefreshSessionState(
            refreshing: true,
            message: '正在刷新搜索状态与结果...',
          ),
        ),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('正在刷新搜索状态与结果...'), findsWidgets);
  final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
  expect(button.onPressed, isNull);
});

testWidgets('SearchSettingsPage index action uses combined refresh controller flow', (tester) async {
  late _RecordingSearchIndexController controller;
  final pendingItem = SearchIndexPendingItem(
    sourceId: 'secret-1',
    sourceType: SearchSourceType.secret,
    title: '邮箱账号',
    updatedAt: DateTime(2026, 4, 21, 10, 0),
    plainTextHash: 'hash-refresh-controller',
    indexPlainText: '邮箱账号\nuser@example.com',
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(ready: true, reason: '本地语义检索模型已就绪'),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: [pendingItem],
          ),
        ),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        searchIndexControllerProvider.overrideWith((ref) {
          controller = _RecordingSearchIndexController(ref: ref);
          return controller;
        }),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.text('立即构建索引').first);
  await tester.pump();

  expect(controller.refreshCalls, 1);
});
```

Extend the existing `_RecordingSearchIndexController` test double in `test/features/search/presentation/search_settings_page_test.dart` with the same `refreshCalls` and `indexPendingAndRefresh()` override used in the SearchPage test file.

- [ ] **Step 2: Run the SearchSettingsPage refresh-controller test to verify failure**

Run:

```powershell
flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage index action uses combined refresh controller flow"
```

Expected: FAIL because the page still calls `indexPending()`.

- [ ] **Step 3: Consume the shared refresh-session state in SearchSettingsPage**

Update `SearchSettingsPage.build` to watch the refresh session:

```dart
final refreshSession = ref.watch(searchRefreshSessionProvider);
```

Pass it into `_SemanticReadinessCard` and `_IndexStatusCard`.

Update `_IndexStatusCard` signature:

```dart
const _IndexStatusCard({required this.status, required this.summary, required this.refreshSession});

final SearchRefreshSessionState refreshSession;
```

Change `_handleIndexAction` to call:

```dart
await ref.read(searchIndexControllerProvider).indexPendingAndRefresh();
```

In `_IndexStatusCard`, add the shared refresh hint above the CTA block:

```dart
if (refreshSession.refreshing && refreshSession.message != null) ...[
  const SizedBox(height: 8),
  Row(
    children: [
      const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(refreshSession.message!)),
    ],
  ),
],
```

Disable the CTA while refreshing and show inline loading in the button icon just like SearchPage.

Update `_SemanticReadinessCard` signature:

```dart
const _SemanticReadinessCard({
  required this.readiness,
  required this.scope,
  required this.indexStatus,
  required this.summary,
  required this.refreshSession,
});

final SearchRefreshSessionState refreshSession;
```

Render the shared refresh hint inside the top card as well:

```dart
if (refreshSession.refreshing && refreshSession.message != null) ...[
  const SizedBox(height: 12),
  Row(
    children: [
      const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(refreshSession.message!)),
    ],
  ),
],
```

Also change the action chip callback in `_SemanticReadinessCard` to call `_handleIndexAction(context, ref)` so the shared refresh path is always used.

- [ ] **Step 4: Run the full SearchSettingsPage test file**

Run:

```powershell
flutter test test/features/search/presentation/search_settings_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the SearchSettingsPage refresh closure**

```powershell
git add "lib/features/search/presentation/search_settings_page.dart" "test/features/search/presentation/search_settings_page_test.dart"
git commit -m "feat: add refresh closure to search settings page"
```

---

### Task 4: Verify end-to-end refresh closure slice

**Files:**
- Modify: `lib/features/search/application/search_providers.dart` (if needed)
- Modify: `lib/features/search/presentation/search_page.dart` (if needed)
- Modify: `lib/features/search/presentation/search_settings_page.dart` (if needed)
- Modify: `lib/features/search/presentation/search_status_summary.dart` (if needed)
- Test: `test/features/search/presentation/search_page_test.dart`
- Test: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Run both search presentation test files together**

Run:

```powershell
flutter test test/features/search/presentation/search_page_test.dart; if ($?) { flutter test test/features/search/presentation/search_settings_page_test.dart }
```

Expected: both files PASS.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run LSP diagnostics on changed files**

Check these files:

```text
lib/features/search/application/search_providers.dart
lib/features/search/presentation/search_page.dart
lib/features/search/presentation/search_settings_page.dart
lib/features/search/presentation/search_status_summary.dart
test/features/search/presentation/search_page_test.dart
test/features/search/presentation/search_settings_page_test.dart
```

Expected: clean diagnostics or only pre-existing unrelated issues.

- [ ] **Step 4: If verification fails, make the minimal fix and rerun only the failing command**

Use this rule:

```text
If a widget test fails, fix only the smallest mismatch in refresh-state expectations and rerun that specific test file.
If analyze fails, fix only the reported issue and rerun flutter analyze.
If diagnostics fail, fix the exact changed-file issue and rerun diagnostics on that file.
```

- [ ] **Step 5: Commit the verified feature slice**

```powershell
git add "lib/features/search/application/search_providers.dart" "lib/features/search/presentation/search_page.dart" "lib/features/search/presentation/search_settings_page.dart" "lib/features/search/presentation/search_status_summary.dart" "test/features/search/presentation/search_page_test.dart" "test/features/search/presentation/search_settings_page_test.dart"
git commit -m "feat: add shared refresh closure after indexing"
```

---

## Self-Review

- Spec coverage:
  - Shared refresh session state: Task 1
  - Combined controller flow after indexing: Task 1
  - SearchPage loading + refresh hint: Task 2
  - SearchSettingsPage loading + refresh hint: Task 3
  - Shared cross-page UI state: Tasks 2 and 3
  - Verification: Task 4
- Placeholder scan: no `TODO`, `TBD`, or abstract placeholder tasks remain.
- Type consistency: `SearchRefreshSessionState` and `searchRefreshSessionProvider` are introduced once and reused consistently across later tasks.
