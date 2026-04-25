# Model Summary Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align model capability summary wording between `SearchSettingsPage` and `ModelManagementPage`, and add one lightweight deployment-status line using existing state only.

**Architecture:** Keep the existing page structures intact and limit changes to presentation code. Reuse the current `SearchSettingsPage` summary format as the baseline, then add a small formatter strategy for deployment-status lines using only existing registry/catalog/selection state. Cover the slice with focused widget tests for both pages.

**Tech Stack:** Flutter, Dart, flutter_test, flutter_riverpod

---

## File Structure

- Modify: `lib/features/search/presentation/search_settings_page.dart`
  - Keep the existing active-model summary formatter.
  - Add one deployment-status formatter for the active embedding model.
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
  - Enrich installed-model rows with aligned summary text and deployment-status text.
  - Add a lightweight deployment-status line to catalog entry tiles.
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
  - Add focused widget tests for deployment-status text.
- Create: `test/features/ai_models/presentation/model_management_page_test.dart`
  - Add focused widget tests for installed-model summary alignment and catalog deployment-status messaging.

No new production layers, routes, or providers are needed.

### Task 1: Add failing tests for search settings deployment-status messaging

**Files:**
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
- Modify: `lib/features/search/presentation/search_settings_page.dart`

- [ ] **Step 1: Write the failing widget test for a ready active embedding model**

Add this test near the existing active-model summary tests:

```dart
testWidgets('SearchSettingsPage shows ready deployment status for an installed active model', (
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

  expect(find.text('部署状态：本地文件已就绪，可用于当前语义检索。'), findsOneWidget);
});
```

- [ ] **Step 2: Run the ready-deployment test to verify it fails**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows ready deployment status for an installed active model"`

Expected: FAIL because the deployment-status line is not rendered yet.

- [ ] **Step 3: Write the failing widget test for a missing-file active model**

Add this test below the ready-deployment test:

```dart
testWidgets('SearchSettingsPage shows degraded deployment status when the active model file is missing', (
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
              filePresent: false,
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

  expect(find.text('部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。'), findsOneWidget);
});
```

- [ ] **Step 4: Run the missing-file deployment test to verify it fails**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows degraded deployment status when the active model file is missing"`

Expected: FAIL because the degraded deployment-status line is not rendered yet.

- [ ] **Step 5: Implement the minimal deployment-status formatter in `SearchSettingsPage`**

Inside `_SemanticReadinessCard`, add a tiny formatter and render the line immediately below `_modelSummary(...)` and above the existing explanatory sentence.

Implementation target:

```dart
String _deploymentStatus(ModelRegistryEntry model) {
  if (model.isInstalled) {
    return '部署状态：本地文件已就绪，可用于当前语义检索。';
  }
  return '部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。';
}
```

Render it like:

```dart
Text(
  _deploymentStatus(readiness.activeEmbeddingModel!),
  style: Theme.of(context).textTheme.bodySmall,
),
const SizedBox(height: 6),
```

- [ ] **Step 6: Run both new search-settings deployment tests to verify they pass**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows ready deployment status for an installed active model" && flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage shows degraded deployment status when the active model file is missing"`

Expected: PASS for both tests.

### Task 2: Add failing tests for model-management summary alignment and deployment status

**Files:**
- Create: `test/features/ai_models/presentation/model_management_page_test.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`

- [ ] **Step 1: Create the widget test file with imports and a minimal harness**

Create `test/features/ai_models/presentation/model_management_page_test.dart` with these imports and a `main()` block:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_management_page.dart';

void main() {
  // add tests here
}
```

- [ ] **Step 2: Write the failing test for an installed model row summary + deployment line**

Add this test:

```dart
testWidgets('ModelManagementPage shows aligned installed model summary and ready deployment status', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelCatalogEntriesProvider.overrideWith(
          (ref) async => const <ModelCatalogEntry>[],
        ),
        modelDownloadTasksProvider.overrideWith(
          (ref) async => const <ModelDownloadTask>[],
        ),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [
            ModelRegistryEntry(
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
          ],
        ),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
        ),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(
    find.text('builtin · embedding · Q8 · 版本 1.0.2 · 10.0 MB · RAM ≥ 512MB · 推荐档位 mvp'),
    findsOneWidget,
  );
  expect(find.text('部署状态：本地文件已就绪。'), findsOneWidget);
  expect(find.text('当前语义模型'), findsOneWidget);
});
```

- [ ] **Step 3: Run the installed-model test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows aligned installed model summary and ready deployment status"`

Expected: FAIL because installed-model rows currently only show local path and coarse status text.

- [ ] **Step 4: Write the failing test for a missing-file installed-model record**

Add this test:

```dart
testWidgets('ModelManagementPage shows degraded deployment status for a missing-file registry entry', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelCatalogEntriesProvider.overrideWith(
          (ref) async => const <ModelCatalogEntry>[],
        ),
        modelDownloadTasksProvider.overrideWith(
          (ref) async => const <ModelDownloadTask>[],
        ),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [
            ModelRegistryEntry(
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
              filePresent: false,
            ),
          ],
        ),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('部署状态：本地文件缺失，当前记录不可直接使用。'), findsOneWidget);
  expect(find.text('记录失效'), findsOneWidget);
});
```

- [ ] **Step 5: Run the missing-file installed-model test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows degraded deployment status for a missing-file registry entry"`

Expected: FAIL because the degraded deployment-status line is not rendered yet.

- [ ] **Step 6: Write the failing test for catalog deployment status messaging**

Add this test:

```dart
testWidgets('ModelManagementPage catalog entry shows installed deployment status when local file is ready', (
  tester,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelCatalogEntriesProvider.overrideWith(
          (ref) async => const [
            ModelCatalogEntry(
              id: 'embed-1',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'MiniLM Embedding',
              description: '用于本地语义检索。',
              sizeBytes: 10485760,
              minRamMb: 512,
              recommendedTier: 'mvp',
              sources: <ModelSourceEntry>[],
            ),
          ],
        ),
        modelDownloadTasksProvider.overrideWith(
          (ref) async => const <ModelDownloadTask>[],
        ),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [
            ModelRegistryEntry(
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
          ],
        ),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('部署状态：已下载到本地，可立即用于后续启用或检索配置。'), findsOneWidget);
});
```

- [ ] **Step 7: Run the catalog deployment-status test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage catalog entry shows installed deployment status when local file is ready"`

Expected: FAIL because catalog tiles do not render that deployment-status line yet.

- [ ] **Step 8: Implement the minimal model-management presentation changes**

In `lib/features/ai_models/presentation/model_management_page.dart`:

1. Add a compact summary formatter for `ModelRegistryEntry` that matches `SearchSettingsPage` ordering.
2. Add an installed-model deployment-status formatter:

```dart
String _installedModelDeploymentStatus(ModelRegistryEntry entry) {
  if (entry.isInstalled) {
    return '部署状态：本地文件已就绪。';
  }
  return '部署状态：本地文件缺失，当前记录不可直接使用。';
}
```

3. Update `_InstalledModelsCard` subtitle to render a small `Column` with:
   - aligned summary text
   - deployment-status text
   - optional local path text only if you still need a tertiary line

4. Add a catalog deployment-status formatter in `_CatalogEntryTile`:

```dart
String _catalogDeploymentStatus() {
  if (installedEntry == null) {
    return '部署状态：尚未下载到本地。';
  }
  if (installedEntry!.isInstalled) {
    return '部署状态：已下载到本地，可立即用于后续启用或检索配置。';
  }
  return '部署状态：本地记录存在，但文件缺失，需要重新下载。';
}
```

5. Render that line below the metadata chips and above `_DownloadStatusCard(...)`.

- [ ] **Step 9: Run all model-management page tests to verify they pass**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage"`

Expected: PASS for all new model-management widget tests.

### Task 3: Run focused verification for both pages

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `test/features/search/presentation/search_settings_page_test.dart`
- Create: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Run the full SearchSettingsPage widget test group**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage"`

Expected: PASS.

- [ ] **Step 2: Run the full ModelManagementPage widget test group**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage"`

Expected: PASS.

- [ ] **Step 3: Run Flutter analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Run diagnostics on all changed files**

Check diagnostics for:

- `lib/features/search/presentation/search_settings_page.dart`
- `lib/features/ai_models/presentation/model_management_page.dart`
- `test/features/search/presentation/search_settings_page_test.dart`
- `test/features/ai_models/presentation/model_management_page_test.dart`

Expected: no errors.

- [ ] **Step 5: Review spec alignment before claiming completion**

Confirm that the slice stayed conservative:

- no new providers or routes
- no download / selection behavior changes
- search settings keeps the aligned summary and adds one deployment-status line
- model management adds summary alignment for installed models and deployment-status messaging using existing state only
- catalog tiles keep their existing chips and only gain one compact deployment-status line

- [ ] **Step 6: Do not commit unless explicitly requested**

Leave the work uncommitted unless the user separately asks for a git commit.

---

## Self-Review

### Spec coverage

- Search settings deployment-status line: covered by Task 1.
- Installed-model summary alignment: covered by Task 2.
- Catalog deployment-status line: covered by Task 2.
- Conservative verification without architecture drift: covered by Task 3.

### Placeholder scan

No `TODO`, `TBD`, or vague implementation instructions remain.

### Type consistency

- `ModelRegistryEntry` fields used in the plan match the current code: `provider`, `type`, `quantization`, `version`, `sizeBytes`, `minRamMb`, `recommendedTier`, `localPath`, `enabled`, `filePresent`.
- `ModelCatalogEntry` fields used in the plan match the current code: `id`, `type`, `tier`, `displayName`, `description`, `sizeBytes`, `minRamMb`, `recommendedTier`, `sources`.
- Existing `ActiveModelSelection` usage is preserved as `ActiveModelSelection(activeEmbeddingModelId: ...)`.
