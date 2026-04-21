# Search Settings Blocked Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compact blocked-state guidance actions to `SearchSettingsPage` so users can go to model management, recognize local semantic scope is disabled, and trigger index building directly when the index is actionable.

**Architecture:** Keep the existing `SearchSettingsPage` and semantic readiness card structure intact. Extend the readiness card’s guidance item model so recommendation chips can either navigate or invoke local indexing actions, and cover the new behavior with widget tests written first.

**Tech Stack:** Flutter, Dart, flutter_test, flutter_riverpod, GoRouter

---

## File Structure

- Modify: `lib/features/search/presentation/search_settings_page.dart`
  - Extend `_SemanticReadinessCard` guidance derivation.
  - Allow a guidance item to represent either a route action or an index action.
  - Trigger `searchIndexControllerProvider.indexPending()` from the readiness card when appropriate.
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
  - Add failing widget tests for actionable index guidance labels and tap behavior.
  - Keep the existing blocked guidance and model navigation coverage.

No new production files are needed for this tranche.

### Task 1: Add failing tests for actionable guidance labels

**Files:**
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
- Modify: `lib/features/search/presentation/search_settings_page.dart`

- [ ] **Step 1: Write the failing test for first-time actionable indexing guidance**

```dart
testWidgets('SearchSettingsPage shows build-index guidance when pending items are actionable', (
  tester,
) async {
  final pendingItem = SearchIndexPendingItem(
    sourceId: 'secret-1',
    sourceType: SearchSourceType.secret,
    title: '邮箱账号',
    updatedAt: DateTime(2026, 4, 21, 10, 0),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith(
          (ref) async => const SearchScopeConfig.defaults(),
        ),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(
            ready: false,
            reason: '存在待构建索引项',
            activeEmbeddingModel: ModelRegistryEntry(
              id: 'embed-1',
              type: 'embedding',
              provider: 'builtin',
              name: 'MiniLM Embedding',
              version: '1.0',
              sizeBytes: 1024,
              quantization: 'Q8',
              minRamMb: 512,
              recommendedTier: 'mvp',
              localPath: '/data/models/minilm.onnx',
              checksum: 'abc',
              enabled: true,
              installedAt: null,
              filePresent: true,
            ),
          ),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: [pendingItem],
          ),
        ),
        searchIndexSettingsProvider.overrideWith(
          (ref) async => const SearchIndexSettings.defaults(),
        ),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('下一步建议'), findsOneWidget);
  expect(find.text('立即构建索引'), findsOneWidget);
  expect(find.text('刷新本地索引'), findsNothing);
});
```

- [ ] **Step 2: Run the test to verify it fails for the expected reason**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows build-index guidance when pending items are actionable"`

Expected: FAIL because `立即构建索引` is not rendered yet.

- [ ] **Step 3: Write the failing test for refresh guidance after a prior completed index run**

```dart
testWidgets('SearchSettingsPage shows refresh-index guidance after a prior completed index run', (
  tester,
) async {
  final pendingItem = SearchIndexPendingItem(
    sourceId: 'note-1',
    sourceType: SearchSourceType.note,
    title: '恢复码备忘',
    updatedAt: DateTime(2026, 4, 21, 11, 0),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith(
          (ref) async => const SearchScopeConfig.defaults(),
        ),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(
            ready: false,
            reason: '索引需要刷新',
            activeEmbeddingModel: ModelRegistryEntry(
              id: 'embed-1',
              type: 'embedding',
              provider: 'builtin',
              name: 'MiniLM Embedding',
              version: '1.0',
              sizeBytes: 1024,
              quantization: 'Q8',
              minRamMb: 512,
              recommendedTier: 'mvp',
              localPath: '/data/models/minilm.onnx',
              checksum: 'abc',
              enabled: true,
              installedAt: null,
              filePresent: true,
            ),
          ),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: [pendingItem],
            taskState: SearchIndexTaskState(
              lastCompletedAt: DateTime(2026, 4, 21, 9, 30),
              lastIndexedCount: 4,
            ),
          ),
        ),
        searchIndexSettingsProvider.overrideWith(
          (ref) async => const SearchIndexSettings.defaults(),
        ),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('刷新本地索引'), findsOneWidget);
  expect(find.text('立即构建索引'), findsNothing);
});
```

- [ ] **Step 4: Run the refresh-guidance test to verify it fails**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows refresh-index guidance after a prior completed index run"`

Expected: FAIL because `刷新本地索引` is not rendered yet.

- [ ] **Step 5: Implement the minimal production code for actionable guidance labels**

Update the readiness card so it can derive index guidance in addition to model/scope guidance. Change `_SemanticReadinessCard` to a `ConsumerWidget`, add an action-kind field to `_GuidanceItem`, and render an `ActionChip` for both route actions and local index actions.

```dart
class _SemanticReadinessCard extends ConsumerWidget {
  const _SemanticReadinessCard({
    required this.readiness,
    required this.scope,
    required this.indexStatus,
  });

  final SemanticSearchReadiness readiness;
  final SearchScopeConfig scope;
  final SearchIndexStatus indexStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = readiness.ready;
    final guidanceItems = _blockedGuidanceItems();

    return Card(
      color: isReady ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // existing header and pipeline content unchanged
            if (guidanceItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '下一步建议',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in guidanceItems)
                    if (item.route != null || item.action == _GuidanceAction.indexPending)
                      ActionChip(
                        label: Text(item.label),
                        onPressed: () {
                          if (item.route != null) {
                            context.push(item.route!);
                            return;
                          }

                          if (item.action == _GuidanceAction.indexPending) {
                            ref.read(searchIndexControllerProvider).indexPending();
                          }
                        },
                      )
                    else
                      Chip(label: Text(item.label)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_GuidanceItem> _blockedGuidanceItems() {
    final items = <_GuidanceItem>[];

    if (readiness.activeEmbeddingModel == null) {
      items.add(const _GuidanceItem(label: '前往模型管理', route: '/models'));
    }
    if (!scope.allowLocalEmbedding) {
      items.add(const _GuidanceItem(label: '启用本地语义检索'));
    }
    if (indexStatus.readyForIndexing && indexStatus.pendingItems.isNotEmpty) {
      final label = indexStatus.taskState.lastCompletedAt == null ? '立即构建索引' : '刷新本地索引';
      items.add(_GuidanceItem(label: label, action: _GuidanceAction.indexPending));
    }

    return items;
  }
}

enum _GuidanceAction { indexPending }

class _GuidanceItem {
  const _GuidanceItem({required this.label, this.route, this.action});

  final String label;
  final String? route;
  final _GuidanceAction? action;
}
```

- [ ] **Step 6: Run the two tests to verify they pass**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows build-index guidance when pending items are actionable" && flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows refresh-index guidance after a prior completed index run"`

Expected: PASS for both tests.

### Task 2: Add failing tests for non-actionable states and tap behavior

**Files:**
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
- Modify: `lib/features/search/presentation/search_settings_page.dart`

- [ ] **Step 1: Write the failing test that index guidance stays hidden when indexing is blocked**

```dart
testWidgets('SearchSettingsPage does not show index guidance when indexing is not actionable', (
  tester,
) async {
  final pendingItem = SearchIndexPendingItem(
    sourceId: 'secret-1',
    sourceType: SearchSourceType.secret,
    title: '邮箱账号',
    updatedAt: DateTime(2026, 4, 21, 10, 0),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith(
          (ref) async => const SearchScopeConfig.defaults(),
        ),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(
            ready: false,
            reason: '索引引擎未就绪',
            activeEmbeddingModel: ModelRegistryEntry(
              id: 'embed-1',
              type: 'embedding',
              provider: 'builtin',
              name: 'MiniLM Embedding',
              version: '1.0',
              sizeBytes: 1024,
              quantization: 'Q8',
              minRamMb: 512,
              recommendedTier: 'mvp',
              localPath: '/data/models/minilm.onnx',
              checksum: 'abc',
              enabled: true,
              installedAt: null,
              filePresent: true,
            ),
          ),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => SearchIndexStatus(
            engineReady: false,
            engineReason: '索引引擎未就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: [pendingItem],
          ),
        ),
        searchIndexSettingsProvider.overrideWith(
          (ref) async => const SearchIndexSettings.defaults(),
        ),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('立即构建索引'), findsNothing);
  expect(find.text('刷新本地索引'), findsNothing);
});
```

- [ ] **Step 2: Run the hidden-guidance test to verify it fails only if the implementation is wrong**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage does not show index guidance when indexing is not actionable"`

Expected: PASS immediately if the minimal implementation already satisfies the behavior. If it fails, fix production code instead of weakening the test.

- [ ] **Step 3: Write the failing test for tapping the index guidance action**

Use a fake controller to observe whether `indexPending()` is called.

```dart
class _FakeSearchIndexController extends SearchIndexController {
  _FakeSearchIndexController() : super(repository: _NoopSearchRepository());

  int calls = 0;

  @override
  Future<void> indexPending() async {
    calls++;
  }
}
```

```dart
testWidgets('SearchSettingsPage index guidance triggers pending indexing', (
  tester,
) async {
  final fakeController = _FakeSearchIndexController();
  final pendingItem = SearchIndexPendingItem(
    sourceId: 'secret-1',
    sourceType: SearchSourceType.secret,
    title: '邮箱账号',
    updatedAt: DateTime(2026, 4, 21, 10, 0),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith(
          (ref) async => const SearchScopeConfig.defaults(),
        ),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(
            ready: false,
            reason: '存在待构建索引项',
            activeEmbeddingModel: ModelRegistryEntry(
              id: 'embed-1',
              type: 'embedding',
              provider: 'builtin',
              name: 'MiniLM Embedding',
              version: '1.0',
              sizeBytes: 1024,
              quantization: 'Q8',
              minRamMb: 512,
              recommendedTier: 'mvp',
              localPath: '/data/models/minilm.onnx',
              checksum: 'abc',
              enabled: true,
              installedAt: null,
              filePresent: true,
            ),
          ),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: [pendingItem],
          ),
        ),
        searchIndexSettingsProvider.overrideWith(
          (ref) async => const SearchIndexSettings.defaults(),
        ),
        searchIndexControllerProvider.overrideWithValue(fakeController),
      ],
      child: const MaterialApp(home: SearchSettingsPage()),
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.text('立即构建索引'));
  await tester.pump();

  expect(fakeController.calls, 1);
});
```

- [ ] **Step 4: Run the tap-behavior test to verify it fails first**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage index guidance triggers pending indexing"`

Expected: FAIL before the wiring is correct, then PASS after the action chip is hooked to the controller.

- [ ] **Step 5: Add the smallest code required so the tap behavior is fully wired**

Ensure the `ActionChip` press handler calls `ref.read(searchIndexControllerProvider).indexPending()` only for `_GuidanceAction.indexPending`, with no additional side effects.

```dart
onPressed: () {
  if (item.route != null) {
    context.push(item.route!);
    return;
  }

  if (item.action == _GuidanceAction.indexPending) {
    ref.read(searchIndexControllerProvider).indexPending();
  }
},
```

- [ ] **Step 6: Run the three behavior tests together**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage"`

Expected: All `SearchSettingsPage` widget tests PASS, including the existing blocked-state and model-navigation tests.

### Task 3: Verify and finish the tranche

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Run Flutter analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 2: Run LSP diagnostics on changed files**

Check diagnostics for:

- `lib/features/search/presentation/search_settings_page.dart`
- `test/features/search/presentation/search_settings_page_test.dart`

Expected: no errors.

- [ ] **Step 3: Review for spec coverage before claiming completion**

Confirm the implemented behavior matches each spec requirement:

- Missing model shows `前往模型管理`
- Disabled local semantic scope shows `启用本地语义检索`
- Actionable index shows `立即构建索引` or `刷新本地索引`
- Non-actionable index state shows no index action
- Model navigation still works
- Index action triggers `indexPending()`

- [ ] **Step 4: Do not commit unless explicitly requested**

Leave the work uncommitted unless the user separately asks for a git commit.

---

## Self-Review

### Spec coverage

- Existing structure preserved: covered by Tasks 1 and 2 because the readiness card is extended rather than redesigned.
- Blocked guidance for model and local semantic scope: covered by existing tests plus Task 3 review.
- Direct actionable index guidance with two labels: covered by Task 1.
- No index action when not actionable: covered by Task 2.
- TDD: every new behavior is introduced with a failing test first in Tasks 1 and 2.
- Verification: covered by Task 3.

### Placeholder scan

No `TODO`, `TBD`, or unspecified “handle appropriately” instructions remain.

### Type consistency

- `searchIndexControllerProvider` is the existing provider used by both `_IndexStatusCard` and the planned readiness-card action.
- `SearchIndexStatus.taskState.lastCompletedAt` is used consistently for the refresh/build label split.
- `_GuidanceAction.indexPending` and `_GuidanceItem.action` are defined in Task 1 before being referenced later.
