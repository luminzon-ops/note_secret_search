# Model Catalog Real Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Milestone 6 from a placeholder built-in model catalog to a realistic embedding catalog with manual source selection and source-aware download task handling.

**Architecture:** Keep the asset-backed catalog as the current source of truth, but make the UI respect an explicit selected source instead of always using the first source. Align download task lookup with `(modelId, sourceId)` so source switching does not reuse or corrupt the wrong task state. Preserve the checksum verification chain already implemented.

**Tech Stack:** Flutter, Dart, Riverpod, Sqflite SQLCipher, Flutter widget tests, Flutter unit tests

---

## File Structure

- Modify: `assets/model_catalog/built_in_catalog.json`
  - Replace placeholder-only source definition with a more realistic embedding entry and multiple sources.
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
  - Add manual source selection UI and wire actions to the selected source.
- Modify: `lib/features/ai_models/domain/model_download_repository.dart`
  - Add a source-aware lookup contract.
- Modify: `lib/features/ai_models/infrastructure/sqlite_model_download_repository.dart`
  - Implement source-aware latest-task lookup.
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
  - Use source-aware task resolution for enqueue/pause/failure/start flows.
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
  - Add widget tests for source selection and selected-source download behavior.
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`
  - Add source-aware task isolation tests.
- Modify: `第一阶段产品进度报告.md`
  - Update Milestone 6 progress wording after implementation.

### Task 1: Add source-aware repository coverage first

**Files:**
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`
- Modify: `lib/features/ai_models/domain/model_download_repository.dart`
- Modify: `lib/features/ai_models/infrastructure/sqlite_model_download_repository.dart`

- [ ] **Step 1: Write a failing source-aware task test**

Add a test proving the same model can have different latest tasks per source:

```dart
test('startDownload keeps source-specific tasks separate for the same model', () async {
  final downloadRepository = _MemoryDownloadRepository();
  final registryRepository = _MemoryRegistryRepository();
  final bridge = _RecordingEmbeddingRuntimeBridge();
  final downloadService = _FakeDownloadService(
    result: const ModelDownloadResult(
      localPath: '/models/embed-1.onnx',
      totalBytes: 4096,
      verifiedChecksum: 'sha256:verified-source-b',
    ),
  );

  downloadRepository.tasksById['task-source-a'] = ModelDownloadTask(
    id: 'task-source-a',
    modelId: 'embed-1',
    sourceId: 'source-a',
    status: ModelDownloadStatus.paused,
    totalBytes: 4096,
    downloadedBytes: 1024,
    averageSpeed: null,
    errorMessage: null,
    resumable: true,
    createdAt: DateTime(2026, 4, 26, 10, 0),
    updatedAt: DateTime(2026, 4, 26, 10, 1),
  );

  final container = ProviderContainer(
    overrides: [
      modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
      modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
      modelDownloadServiceProvider.overrideWithValue(downloadService),
      embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
    ],
  );

  addTearDown(container.dispose);

  await container.read(modelDownloadControllerProvider).startDownload(
        entry: const ModelCatalogEntry(
          id: 'embed-1',
          type: 'embedding',
          tier: 'mvp',
          displayName: 'MiniLM Embedding',
          description: '用于本地语义检索。',
          sizeBytes: 4096,
          minRamMb: 512,
          recommendedTier: 'mvp',
          sources: <ModelSourceEntry>[
            ModelSourceEntry(
              id: 'source-b',
              label: '备选镜像',
              url: 'https://example.com/embed-1-b.onnx',
              checksum: 'sha256:verified-source-b',
            ),
          ],
        ),
        source: const ModelSourceEntry(
          id: 'source-b',
          label: '备选镜像',
          url: 'https://example.com/embed-1-b.onnx',
          checksum: 'sha256:verified-source-b',
        ),
      );

  expect(downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status, ModelDownloadStatus.paused);
  expect(downloadRepository.tasksByModelAndSource('embed-1', 'source-b')?.status, ModelDownloadStatus.completed);
});
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart --plain-name "startDownload keeps source-specific tasks separate for the same model"`

Expected: FAIL because the in-memory repository and production repository only support lookup by `modelId`.

- [ ] **Step 3: Add a source-aware repository contract and implementation**

Add a new repository method:

```dart
abstract class ModelDownloadRepository {
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId);
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(String modelId, String sourceId);
  Future<List<ModelDownloadTask>> listTasks();
  Future<void> saveTask(ModelDownloadTask task);
}
```

Implement it in SQLite using:

```dart
@override
Future<ModelDownloadTask?> findLatestTaskByModelAndSource(String modelId, String sourceId) async {
  final db = await _database.database;
  final rows = await db.query(
    DatabaseSchema.downloadTasks,
    where: 'model_id = ? AND source_id = ?',
    whereArgs: <Object>[modelId, sourceId],
    orderBy: 'updated_at DESC',
    limit: 1,
  );

  if (rows.isEmpty) {
    return null;
  }

  return _mapTask(rows.first);
}
```

- [ ] **Step 4: Re-run the focused test and verify it now fails later in controller logic or passes if repository wiring is sufficient**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart --plain-name "startDownload keeps source-specific tasks separate for the same model"`

Expected: Either PASS or move failure deeper into the controller, proving the repository contract is now in place.

### Task 2: Make controller flows source-aware

**Files:**
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`

- [ ] **Step 1: Extend the failing tests around pause/reuse behavior**

Add a second focused test:

```dart
test('pause only affects the latest task for the selected source', () async {
  final downloadRepository = _MemoryDownloadRepository();
  final registryRepository = _MemoryRegistryRepository();
  final downloadService = _FakeDownloadService(
    result: const ModelDownloadResult(
      localPath: '/models/embed-1.onnx',
      totalBytes: 4096,
      verifiedChecksum: 'sha256:verified-source-a',
    ),
  );

  downloadRepository.tasksById['task-source-a'] = _task('task-source-a', 'embed-1', 'source-a');
  downloadRepository.tasksById['task-source-b'] = _task('task-source-b', 'embed-1', 'source-b');

  final container = ProviderContainer(
    overrides: [
      modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
      modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
      modelDownloadServiceProvider.overrideWithValue(downloadService),
    ],
  );

  addTearDown(container.dispose);

  await container.read(modelDownloadControllerProvider).pause('embed-1', sourceId: 'source-b');

  expect(downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status, isNot(ModelDownloadStatus.paused));
  expect(downloadRepository.tasksByModelAndSource('embed-1', 'source-b')?.status, ModelDownloadStatus.paused);
});
```

- [ ] **Step 2: Run the focused pause test and verify it fails**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart --plain-name "pause only affects the latest task for the selected source"`

Expected: FAIL because `pause` currently accepts only `modelId`.

- [ ] **Step 3: Update controller methods to resolve tasks by `(modelId, sourceId)` where applicable**

Key changes:

```dart
Future<void> enqueueDownload({
  required String modelId,
  required String sourceId,
  required int? totalBytes,
}) async {
  final existing = await _repository.findLatestTaskByModelAndSource(modelId, sourceId);
  // existing logic continues
}

Future<void> pause(String modelId, {required String sourceId}) async {
  final task = await _repository.findLatestTaskByModelAndSource(modelId, sourceId);
  if (task == null) {
    return;
  }

  _downloadService.cancel(task.id);

  await _repository.saveTask(
    task.copyWith(
      status: ModelDownloadStatus.paused,
      updatedAt: DateTime.now(),
    ),
  );
  _ref.invalidate(modelDownloadTasksProvider);
}
```

Within `startDownload`, all lookup operations that are acting on the active source should use `findLatestTaskByModelAndSource(entry.id, source.id)`.

- [ ] **Step 4: Re-run the application tests**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart`

Expected: PASS

### Task 3: Add manual source selection to model management UI

**Files:**
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`

- [ ] **Step 1: Write a failing widget test for multi-source selection**

Add a test like:

```dart
testWidgets('ModelManagementPage lets the user switch the selected download source', (tester) async {
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
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-a',
                  label: 'GitHub Releases',
                  url: 'https://example.com/a.onnx',
                  checksum: 'sha256:source-a',
                ),
                ModelSourceEntry(
                  id: 'source-b',
                  label: '备用镜像',
                  url: 'https://example.com/b.onnx',
                  checksum: 'sha256:source-b',
                ),
              ],
            ),
          ],
        ),
        modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
        modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
        embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
        modelDownloadControllerProvider.overrideWith((ref) => _RecordingModelDownloadController(ref: ref)),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();
  expect(find.text('当前下载源：GitHub Releases'), findsOneWidget);

  await tester.tap(find.text('GitHub Releases'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('备用镜像').last);
  await tester.pumpAndSettle();

  expect(find.text('当前下载源：备用镜像'), findsOneWidget);
});
```

- [ ] **Step 2: Run the widget test and verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage lets the user switch the selected download source"`

Expected: FAIL because the page has no source selector and still treats `entry.sources.first` as primary.

- [ ] **Step 3: Implement source selection UI with local state per catalog entry**

Add a small stateful widget wrapper around the catalog entry tile so it can store the currently selected source id. The render contract should be:

```dart
class _CatalogEntryTile extends ConsumerStatefulWidget {
  const _CatalogEntryTile({
    required this.entry,
    required this.latestTask,
    required this.installedEntry,
    required this.runtimeState,
  });

  // existing fields
}

class _CatalogEntryTileState extends ConsumerState<_CatalogEntryTile> {
  late String? _selectedSourceId;

  @override
  void initState() {
    super.initState();
    _selectedSourceId = widget.entry.sources.isEmpty ? null : widget.entry.sources.first.id;
  }

  ModelSourceEntry? get _selectedSource {
    for (final source in widget.entry.sources) {
      if (source.id == _selectedSourceId) {
        return source;
      }
    }
    return widget.entry.sources.isEmpty ? null : widget.entry.sources.first;
  }
}
```

Render a source selector only when there are multiple sources. The CTA must call:

```dart
controller.startDownload(entry: widget.entry, source: _selectedSource!);
```

Retry CTA must also use `_selectedSource!`.

- [ ] **Step 4: Re-run the widget tests**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart`

Expected: PASS

### Task 4: Make the built-in catalog realistic enough for the UI and report

**Files:**
- Modify: `assets/model_catalog/built_in_catalog.json`
- Modify: `第一阶段产品进度报告.md`
- Modify: `test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`

- [ ] **Step 1: Write/update the asset parsing test for multiple sources**

Add assertions proving two sources are parsed:

```dart
expect(catalog.single.sources, hasLength(2));
expect(catalog.single.sources.first.label, 'GitHub Releases');
expect(catalog.single.sources.last.label, '备用镜像');
```

- [ ] **Step 2: Run the parsing test and verify it fails**

Run: `flutter test test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`

Expected: FAIL until the fixture/test data and asset are updated consistently.

- [ ] **Step 3: Update the built-in catalog and report wording**

In `assets/model_catalog/built_in_catalog.json`, change the placeholder-only entry into a realistic embedding entry with two explicit sources. Keep the schema exactly the same. At minimum:

```json
{
  "id": "embed_min_cn_v1",
  "type": "embedding",
  "tier": "minimum",
  "display_name": "内置最小版 Embedding",
  "description": "优先用于本地语义检索的轻量 embedding 模型。",
  "size_bytes": 157286400,
  "min_ram_mb": 3072,
  "recommended_tier": "tier_1",
  "source_list": [
    {
      "id": "github-release",
      "label": "GitHub Releases",
      "url": "<chosen-url-a>",
      "checksum": "<real-sha256-a>"
    },
    {
      "id": "mirror-cn",
      "label": "备用镜像",
      "url": "<chosen-url-b>",
      "checksum": "<real-sha256-b>"
    }
  ]
}
```

In `第一阶段产品进度报告.md`, update Milestone 6 wording to reflect:

1. built-in catalog now has a more realistic embedding entry,
2. manual source selection exists,
3. task handling is source-aware,
4. automatic failover / signatures / resume still remain pending.

- [ ] **Step 4: Re-run the parsing test and verify it passes**

Run: `flutter test test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`

Expected: PASS

### Task 5: Final verification

**Files:**
- Verify: `assets/model_catalog/built_in_catalog.json`
- Verify: `lib/features/ai_models/domain/model_download_repository.dart`
- Verify: `lib/features/ai_models/infrastructure/sqlite_model_download_repository.dart`
- Verify: `lib/features/ai_models/application/model_download_providers.dart`
- Verify: `lib/features/ai_models/presentation/model_management_page.dart`
- Verify: `test/features/ai_models/application/model_download_providers_test.dart`
- Verify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Verify: `test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`
- Verify: `第一阶段产品进度报告.md`

- [ ] **Step 1: Run all related ai_models tests**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/application/model_selection_providers_test.dart test/features/ai_models/presentation/model_management_page_test.dart test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`

Expected: PASS

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Run LSP diagnostics on changed ai_models code**

Check diagnostics for:

1. `lib/features/ai_models`
2. `test/features/ai_models`

Expected: zero errors.

- [ ] **Step 4: Re-run the most critical focused tests**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart --plain-name "startDownload keeps source-specific tasks separate for the same model"`

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage lets the user switch the selected download source"`

Expected: PASS
