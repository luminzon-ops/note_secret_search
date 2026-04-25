# Search Settings Model Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance the `SearchSettingsPage` semantic-readiness card so the active local embedding model shows a richer, user-readable capability summary including version, model size, minimum RAM, and recommended device tier.

**Architecture:** Keep the existing search settings layout unchanged and only improve the summary text shown for `readiness.activeEmbeddingModel`. Extend the summary formatting in `search_settings_page.dart` and cover the new text output with focused widget tests in `search_settings_page_test.dart`.

**Tech Stack:** Flutter, Dart, flutter_test, flutter_riverpod

---

## File Structure

- Modify: `lib/features/search/presentation/search_settings_page.dart`
  - Expand `_modelSummary(ModelRegistryEntry model)` into a richer formatter.
  - Keep the summary compact and diagnostics-friendly.
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
  - Add focused widget tests for the richer model summary output.

No new production files are needed for this tranche.

### Task 1: Add failing tests for richer model summary details

**Files:**
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
- Modify: `lib/features/search/presentation/search_settings_page.dart`

- [ ] **Step 1: Write the failing test for a full model capability summary**

```dart
testWidgets('SearchSettingsPage shows detailed active model summary when capability metadata exists', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(
            ready: true,
            reason: '本地语义检索可用',
            activeEmbeddingModel: ModelRegistryEntry(
              id: 'embed-1',
              type: 'embedding',
              provider: 'builtin',
              name: 'MiniLM Embedding',
              version: '1.0.2',
              sizeBytes: 10485760,
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
          (ref) async => const SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: <SearchIndexPendingItem>[],
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

  expect(find.textContaining('builtin · embedding · Q8'), findsOneWidget);
  expect(find.textContaining('版本 1.0.2'), findsOneWidget);
  expect(find.textContaining('10.0 MB'), findsOneWidget);
  expect(find.textContaining('RAM ≥ 512MB'), findsOneWidget);
  expect(find.textContaining('推荐档位 mvp'), findsOneWidget);
});
```

- [ ] **Step 2: Run the test to verify it fails for the expected reason**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows detailed active model summary when capability metadata exists"`

Expected: FAIL because the current summary only shows provider/type/quantization.

- [ ] **Step 3: Write the failing test for sparse model metadata**

```dart
testWidgets('SearchSettingsPage omits absent model metadata from the active model summary', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchScopeConfigProvider.overrideWith((ref) async => const SearchScopeConfig.defaults()),
        semanticSearchReadinessProvider.overrideWith(
          (ref) async => const SemanticSearchReadiness(
            ready: true,
            reason: '本地语义检索可用',
            activeEmbeddingModel: ModelRegistryEntry(
              id: 'embed-1',
              type: 'embedding',
              provider: 'builtin',
              name: 'MiniLM Embedding',
              version: null,
              sizeBytes: null,
              quantization: null,
              minRamMb: null,
              recommendedTier: null,
              localPath: '/data/models/minilm.onnx',
              checksum: 'abc',
              enabled: true,
              installedAt: null,
              filePresent: true,
            ),
          ),
        ),
        searchIndexStatusProvider.overrideWith(
          (ref) async => const SearchIndexStatus(
            engineReady: true,
            engineReason: '索引引擎已就绪',
            hasActiveEmbeddingModel: true,
            pendingItems: <SearchIndexPendingItem>[],
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

  expect(find.text('builtin · embedding'), findsOneWidget);
  expect(find.textContaining('版本'), findsNothing);
  expect(find.textContaining('RAM ≥'), findsNothing);
  expect(find.textContaining('推荐档位'), findsNothing);
});
```

- [ ] **Step 4: Run the sparse-metadata test to verify it fails**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage omits absent model metadata from the active model summary"`

Expected: FAIL because the formatter is not yet selective enough for the new shape.

- [ ] **Step 5: Implement the minimal richer summary formatter**

Update `_modelSummary(ModelRegistryEntry model)` so it builds a compact list of available segments in this order:

1. provider
2. type
3. quantization (if present)
4. `版本 <version>` (if present)
5. human-readable size like `10.0 MB` (if present)
6. `RAM ≥ <minRamMb>MB` (if present)
7. `推荐档位 <recommendedTier>` (if present)

Use a small helper for byte formatting, but keep all code in `search_settings_page.dart`.

```dart
String _modelSummary(ModelRegistryEntry model) {
  final segments = <String>[model.provider, model.type];
  if (model.quantization != null && model.quantization!.isNotEmpty) {
    segments.add(model.quantization!);
  }
  if (model.version != null && model.version!.isNotEmpty) {
    segments.add('版本 ${model.version!}');
  }
  if (model.sizeBytes != null && model.sizeBytes! > 0) {
    segments.add(_formatModelSize(model.sizeBytes!));
  }
  if (model.minRamMb != null && model.minRamMb! > 0) {
    segments.add('RAM ≥ ${model.minRamMb}MB');
  }
  if (model.recommendedTier != null && model.recommendedTier!.isNotEmpty) {
    segments.add('推荐档位 ${model.recommendedTier!}');
  }
  return segments.join(' · ');
}

String _formatModelSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) {
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
  return '${mb.toStringAsFixed(1)} MB';
}
```

- [ ] **Step 6: Run both new tests to verify they pass**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows detailed active model summary when capability metadata exists" && flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage omits absent model metadata from the active model summary"`

Expected: PASS for both tests.

### Task 2: Run focused verification for the search settings page

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Run the full search settings widget test group**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage"`

Expected: All `SearchSettingsPage` widget tests PASS.

- [ ] **Step 2: Run Flutter analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Run LSP diagnostics on both changed files**

Check diagnostics for:

- `lib/features/search/presentation/search_settings_page.dart`
- `test/features/search/presentation/search_settings_page_test.dart`

Expected: no errors.

- [ ] **Step 4: Review spec alignment before claiming completion**

Confirm the slice stays conservative:

- no new page or route added
- no change to search settings page structure
- active model capability summary is richer and more readable
- absent metadata is omitted rather than shown as fake placeholders

- [ ] **Step 5: Do not commit unless explicitly requested**

Leave the work uncommitted unless the user separately asks for a git commit.

---

## Self-Review

### Spec coverage

- Keeps the tranche inside existing search/model-readiness UX: covered by Task 1 and Task 2.
- Avoids scope drift into provider integration or ONNX runtime: covered by the narrow formatter-only implementation.
- Preserves current layout: covered by Task 2 review.

### Placeholder scan

No `TODO`, `TBD`, or vague implementation instructions remain.

### Type consistency

- Uses existing `ModelRegistryEntry` fields: `provider`, `type`, `quantization`, `version`, `sizeBytes`, `minRamMb`, `recommendedTier`.
- Formatter helper names are defined before later verification steps refer to them.
