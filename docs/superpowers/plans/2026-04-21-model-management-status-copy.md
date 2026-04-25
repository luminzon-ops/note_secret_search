# Model Management Status Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify `ModelManagementPage` status labels, chips, deployment copy, and lightweight download-task wording into one consistent status language while preserving behavior and layout.

**Architecture:** Keep all existing state derivation and widget structure intact. Centralize reusable status wording in the existing presentation formatter where appropriate, then update `ModelManagementPage` copy so row labels, chips, deployment sentences, and light task-state wording all follow the same semantic vocabulary.

**Tech Stack:** Flutter, Dart, flutter_test, flutter_riverpod

---

## File Structure

- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
  - Update trailing labels, chips, deployment-related wording, and lightweight download-task wording.
- Modify: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
  - Expand or adjust status-copy helpers when the wording is reused in multiple places.
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
  - Add or update widget tests for the new unified status labels and copy.
- Optionally modify: `test/features/ai_models/presentation/model_presentation_formatter_test.dart`
  - Only if shared formatter wording changes.

No provider, repository, or domain-layer changes are needed.

### Task 1: Add failing tests for unified installed-model row labels

**Files:**
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`

- [ ] **Step 1: Update the inactive-installed row expectation to the new wording**

In `model_management_page_test.dart`, add this test below the current active-row test:

```dart
testWidgets('ModelManagementPage shows 已安装模型 for an installed but inactive model', (
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
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
        modelDownloadControllerProvider.overrideWith(
          (ref) => _FakeModelDownloadController(ref: ref),
        ),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('已安装模型'), findsOneWidget);
});
```

- [ ] **Step 2: Run the inactive-installed row test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows 已安装模型 for an installed but inactive model"`

Expected: FAIL because the row still shows `已安装`.

- [ ] **Step 3: Update the degraded row expectation to the new wording**

In the existing degraded-row test, change:

```dart
expect(find.text('记录失效'), findsOneWidget);
```

to:

```dart
expect(find.text('本地记录失效'), findsOneWidget);
```

- [ ] **Step 4: Run the degraded-row test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows degraded deployment status for a missing-file registry entry"`

Expected: FAIL because the row still shows `记录失效`.

- [ ] **Step 5: Implement the minimal installed-row label changes**

In `model_management_page.dart`, update the installed-model trailing label logic from:

```dart
activeEmbeddingModelId == entry.id
    ? '当前语义模型'
    : (entry.isInstalled ? '已安装' : '记录失效')
```

to:

```dart
activeEmbeddingModelId == entry.id
    ? '当前语义模型'
    : (entry.isInstalled ? '已安装模型' : '本地记录失效')
```

- [ ] **Step 6: Run both row-label tests to verify they pass**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows 已安装模型 for an installed but inactive model" && flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows degraded deployment status for a missing-file registry entry"`

Expected: PASS for both tests.

### Task 2: Add failing tests for unified chip and deployment wording

**Files:**
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- Optionally modify: `test/features/ai_models/presentation/model_presentation_formatter_test.dart`

- [ ] **Step 1: Add a failing test for the active catalog chip wording**

Add this test to `model_management_page_test.dart`:

```dart
testWidgets('ModelManagementPage catalog chip shows 当前语义模型 for the active embedding model', (
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
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: 'embed-1'),
        ),
        modelDownloadControllerProvider.overrideWith(
          (ref) => _FakeModelDownloadController(ref: ref),
        ),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('当前语义模型'), findsWidgets);
});
```

- [ ] **Step 2: Run the active-chip test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage catalog chip shows 当前语义模型 for the active embedding model"`

Expected: FAIL because the chip still shows `已启用`.

- [ ] **Step 3: Add a failing formatter test for the new ready deployment sentence**

In `model_presentation_formatter_test.dart`, update the installed-ready catalog expectation from:

```dart
'部署状态：已下载到本地，可立即用于后续启用或检索配置。'
```

to:

```dart
'部署状态：本地已就绪，可用于后续启用或检索配置。'
```

- [ ] **Step 4: Run the formatter test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart --plain-name "formatCatalogDeploymentStatus returns ready wording for installed entry"`

Expected: FAIL because the formatter still returns the old sentence.

- [ ] **Step 5: Update the formatter wording and chip wording minimally**

1. In `model_presentation_formatter.dart`, change the ready catalog sentence from:

```dart
return '部署状态：已下载到本地，可立即用于后续启用或检索配置。';
```

to:

```dart
return '部署状态：本地已就绪，可用于后续启用或检索配置。';
```

2. In `model_management_page.dart`, update the installed catalog chip from:

```dart
Chip(label: Text(isActiveEmbeddingModel ? '已启用' : '已安装'))
```

to:

```dart
Chip(label: Text(isActiveEmbeddingModel ? '当前语义模型' : '已安装模型'))
```

- [ ] **Step 6: Run the chip test and formatter test to verify they pass**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage catalog chip shows 当前语义模型 for the active embedding model" && flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart --plain-name "formatCatalogDeploymentStatus returns ready wording for installed entry"`

Expected: PASS.

### Task 3: Add failing tests for lightweight download-task wording updates

**Files:**
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`

- [ ] **Step 1: Add a failing test for the no-task wording**

Add this test to `model_management_page_test.dart`:

```dart
testWidgets('ModelManagementPage shows 下载任务未开始 when no download task exists', (
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
              sources: <ModelSourceEntry>[ModelSourceEntry(id: 'src-1', label: '镜像源', url: 'https://example.com/model')],
            ),
          ],
        ),
        modelDownloadTasksProvider.overrideWith(
          (ref) async => const <ModelDownloadTask>[],
        ),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const <ModelRegistryEntry>[],
        ),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
        modelDownloadControllerProvider.overrideWith(
          (ref) => _FakeModelDownloadController(ref: ref),
        ),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('下载任务未开始'), findsOneWidget);
});
```

- [ ] **Step 2: Run the no-task wording test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows 下载任务未开始 when no download task exists"`

Expected: FAIL because the page still shows `尚未创建下载任务`.

- [ ] **Step 3: Implement the minimal no-task wording change**

In `_DownloadStatusCard`, change:

```dart
title: Text('尚未创建下载任务'),
```

to:

```dart
title: Text('下载任务未开始'),
```

Keep the subtitle unchanged unless the existing sentence becomes inconsistent with the new title.

- [ ] **Step 4: Run the no-task wording test to verify it passes**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage shows 下载任务未开始 when no download task exists"`

Expected: PASS.

### Task 4: Run full verification for the status-copy slice

**Files:**
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Possibly modify: `test/features/ai_models/presentation/model_presentation_formatter_test.dart`

- [ ] **Step 1: Run the full ModelManagementPage widget test group**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage"`

Expected: PASS.

- [ ] **Step 2: Run formatter tests if they changed**

Run: `flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart`

Expected: PASS.

- [ ] **Step 3: Run Flutter analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Run diagnostics on changed files**

Check diagnostics for:

- `lib/features/ai_models/presentation/model_management_page.dart`
- `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- `test/features/ai_models/presentation/model_management_page_test.dart`
- `test/features/ai_models/presentation/model_presentation_formatter_test.dart` (if changed)

Expected: no errors.

- [ ] **Step 5: Review behavior-preserving scope before claiming completion**

Confirm that:

- only copy changed
- button labels did not change
- provider / selection / download behavior did not change
- widget layout remains effectively the same
- status vocabulary is more consistent across row labels, chips, deployment copy, and no-task wording

- [ ] **Step 6: Do not commit unless explicitly requested**

Leave the work uncommitted unless the user separately asks for a git commit.

---

## Self-Review

### Spec coverage

- Installed-row label unification: covered by Task 1.
- Chip and deployment-copy unification: covered by Task 2.
- Lightweight download-task wording refinement: covered by Task 3.
- Behavior-preserving verification: covered by Task 4.

### Placeholder scan

No `TODO`, `TBD`, or vague implementation instructions remain.

### Type consistency

- The plan preserves current `ModelManagementPage` inputs and state derivation.
- It keeps `model_presentation_formatter.dart` as the shared place for reusable status copy when helpful.
- No new domain types or provider APIs are introduced.
