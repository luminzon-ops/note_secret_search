# Milestone 6-A Download Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real resumable downloads and restart recovery to model management so paused or interrupted model downloads can continue from partial files instead of restarting from zero.

**Architecture:** Keep the existing `ModelDownloadTask` table and catalog-driven download flow. Extend `ModelDownloadService` so it can inspect partial files, attempt HTTP Range resume, and explicitly fall back to a clean full download when resume is unsupported. Reconcile persisted task state against the local partial file on provider load so the UI can expose correct `开始下载 / 继续下载 / 重试下载` semantics without adding a new database table.

**Tech Stack:** Flutter, Dart, Riverpod, Dio, `dart:io`, flutter_test.

---

## File Map

### Existing files to modify
- `lib/features/ai_models/infrastructure/model_download_service.dart`
  - Add partial-file inspection and resumable transfer support.
- `lib/features/ai_models/application/model_download_providers.dart`
  - Reconcile persisted task state with local partial files and route start/restart/resume behavior through the controller.
- `lib/features/ai_models/presentation/model_management_page.dart`
  - Surface resume-aware button labels and status copy.

### Existing tests to extend
- `test/features/ai_models/application/model_download_providers_test.dart`
- `test/features/ai_models/presentation/model_management_page_test.dart`

### New test files
- `test/features/ai_models/infrastructure/model_download_service_test.dart`

### No schema change in this plan
- Keep `ModelDownloadTask` and `SqliteModelDownloadRepository` unchanged unless implementation proves a field is truly unavoidable.

---

### Task 1: Add resumable transfer primitives to `ModelDownloadService`

**Files:**
- Modify: `lib/features/ai_models/infrastructure/model_download_service.dart`
- Create: `test/features/ai_models/infrastructure/model_download_service_test.dart`

- [ ] **Step 1: Write the failing infrastructure test for partial-file inspection**

```dart
test('inspectDownloadTarget returns existing partial byte count for a model file', () async {
  final tempDir = await Directory.systemTemp.createTemp('model-download-service');
  addTearDown(() => tempDir.delete(recursive: true));

  final service = TestableModelDownloadService(
    dio: Dio(),
    logger: const AppLogger(),
    applicationSupportDirectory: tempDir,
  );

  final file = File('${tempDir.path}/models/embed-1.onnx');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(List<int>.filled(128, 1));

  final target = await service.inspectDownloadTarget(
    modelId: 'embed-1',
    sourceUrl: 'https://example.com/embed-1.onnx',
  );

  expect(target.localPath, file.path);
  expect(target.existingBytes, 128);
  expect(target.exists, isTrue);
});
```

- [ ] **Step 2: Write the failing infrastructure test for successful resume with Range**

```dart
test('download appends bytes when the source supports HTTP Range resume', () async {
  final tempDir = await Directory.systemTemp.createTemp('model-download-service');
  addTearDown(() => tempDir.delete(recursive: true));

  final adapter = FakeResumeHttpClientAdapter(
    expectedRangeHeader: 'bytes=4-',
    statusCode: 206,
    responseBytes: <int>[5, 6, 7, 8],
  );
  final dio = Dio()..httpClientAdapter = adapter;
  final service = TestableModelDownloadService(
    dio: dio,
    logger: const AppLogger(),
    applicationSupportDirectory: tempDir,
  );

  final file = File('${tempDir.path}/models/embed-1.onnx');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(<int>[1, 2, 3, 4]);

  final result = await service.download(
    taskId: 'task-1',
    modelId: 'embed-1',
    sourceUrl: 'https://example.com/embed-1.onnx',
    expectedChecksum: 'sha256:55e5509f8052998294266ee5b50cb592938191fb5d67f73cac2e60b0276b1bdd',
    resumeFromBytes: 4,
    onProgress: (_) {},
  );

  expect(await file.readAsBytes(), <int>[1, 2, 3, 4, 5, 6, 7, 8]);
  expect(result.resumed, isTrue);
  expect(result.fellBackToRestart, isFalse);
  expect(result.totalBytes, 8);
});
```

- [ ] **Step 3: Write the failing infrastructure test for fallback to full restart when resume is unsupported**

```dart
test('download falls back to a clean full restart when Range is ignored', () async {
  final tempDir = await Directory.systemTemp.createTemp('model-download-service');
  addTearDown(() => tempDir.delete(recursive: true));

  final adapter = FakeResumeHttpClientAdapter(
    expectedRangeHeader: 'bytes=4-',
    statusCode: 200,
    responseBytes: <int>[9, 9, 9, 9],
  );
  final dio = Dio()..httpClientAdapter = adapter;
  final service = TestableModelDownloadService(
    dio: dio,
    logger: const AppLogger(),
    applicationSupportDirectory: tempDir,
  );

  final file = File('${tempDir.path}/models/embed-1.onnx');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(<int>[1, 2, 3, 4]);

  final result = await service.download(
    taskId: 'task-1',
    modelId: 'embed-1',
    sourceUrl: 'https://example.com/embed-1.onnx',
    expectedChecksum: 'sha256:8493100b11a2fe625bcf97fc313f83b580ba4fd2c016221009db93bfe184ee45',
    resumeFromBytes: 4,
    onProgress: (_) {},
  );

  expect(await file.readAsBytes(), <int>[9, 9, 9, 9]);
  expect(result.resumed, isFalse);
  expect(result.fellBackToRestart, isTrue);
});
```

- [ ] **Step 4: Run the new infrastructure tests to verify RED**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/model_download_service_test.dart
```

Expected: FAIL because `ModelDownloadService` does not yet expose target inspection or resumable download behavior.

- [ ] **Step 5: Implement minimal resumable primitives in `model_download_service.dart`**

```dart
class ModelDownloadTarget {
  const ModelDownloadTarget({
    required this.localPath,
    required this.exists,
    required this.existingBytes,
  });

  final String localPath;
  final bool exists;
  final int existingBytes;
}

class ModelDownloadResult {
  const ModelDownloadResult({
    required this.localPath,
    required this.totalBytes,
    required this.verifiedChecksum,
    required this.resumed,
    required this.fellBackToRestart,
    required this.resumable,
  });

  final String localPath;
  final int totalBytes;
  final String verifiedChecksum;
  final bool resumed;
  final bool fellBackToRestart;
  final bool resumable;
}

Future<ModelDownloadTarget> inspectDownloadTarget({
  required String modelId,
  required String sourceUrl,
}) async {
  final targetFile = await _resolveTargetFile(modelId, sourceUrl);
  final exists = await targetFile.exists();
  final existingBytes = exists ? await targetFile.length() : 0;
  return ModelDownloadTarget(
    localPath: targetFile.path,
    exists: exists,
    existingBytes: existingBytes,
  );
}
```

```dart
Future<ModelDownloadResult> download({
  required String taskId,
  required String modelId,
  required String sourceUrl,
  required String expectedChecksum,
  required int resumeFromBytes,
  required void Function(ModelDownloadProgress progress) onProgress,
}) async {
  final target = await inspectDownloadTarget(modelId: modelId, sourceUrl: sourceUrl);
  final targetFile = File(target.localPath);
  final cancelToken = CancelToken();
  _cancelTokens[taskId] = cancelToken;

  var resumed = false;
  var fellBackToRestart = false;
  var resumable = resumeFromBytes > 0;

  try {
    if (resumeFromBytes > 0) {
      final response = await _streamDownload(
        sourceUrl: sourceUrl,
        cancelToken: cancelToken,
        rangeStart: resumeFromBytes,
      );
      if (response.statusCode == 206) {
        resumed = true;
        await _writeResponseBody(targetFile, response.data!, append: true);
      } else {
        resumable = false;
        fellBackToRestart = true;
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        final fullResponse = await _streamDownload(
          sourceUrl: sourceUrl,
          cancelToken: cancelToken,
        );
        await _writeResponseBody(targetFile, fullResponse.data!, append: false);
      }
    } else {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      final response = await _streamDownload(
        sourceUrl: sourceUrl,
        cancelToken: cancelToken,
      );
      await _writeResponseBody(targetFile, response.data!, append: false);
    }

    final fileLength = await targetFile.length();
    final verifiedChecksum = await verifyChecksum(
      filePath: targetFile.path,
      expectedChecksum: expectedChecksum,
    );

    return ModelDownloadResult(
      localPath: targetFile.path,
      totalBytes: fileLength,
      verifiedChecksum: verifiedChecksum,
      resumed: resumed,
      fellBackToRestart: fellBackToRestart,
      resumable: resumable,
    );
  } finally {
    _cancelTokens.remove(taskId);
  }
}
```

- [ ] **Step 6: Re-run the infrastructure tests to verify GREEN**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/model_download_service_test.dart
```

Expected: PASS.

---

### Task 2: Reconcile persisted task state with local partial files and resume in the controller

**Files:**
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`

- [ ] **Step 1: Write the failing application test for resume-from-paused behavior**

```dart
test('startDownload resumes a paused task from existing partial bytes for the same source', () async {
  final downloadRepository = _MemoryDownloadRepository();
  final registryRepository = _MemoryRegistryRepository();
  final downloadService = _ResumeAwareFakeDownloadService(
    inspectTarget: const ModelDownloadTarget(
      localPath: '/models/embed-1.onnx',
      exists: true,
      existingBytes: 1024,
    ),
    result: const ModelDownloadResult(
      localPath: '/models/embed-1.onnx',
      totalBytes: 4096,
      verifiedChecksum: 'sha256:verified-embed-1',
      resumed: true,
      fellBackToRestart: false,
      resumable: true,
    ),
  );

  downloadRepository.tasksById['task-1'] = buildTask(
    id: 'task-1',
    modelId: 'embed-1',
    sourceId: 'source-a',
    status: ModelDownloadStatus.paused,
  );

  final container = ProviderContainer(
    overrides: [
      modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
      modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
      modelDownloadServiceProvider.overrideWithValue(downloadService),
      embeddingRuntimeBridgeProvider.overrideWithValue(_RecordingEmbeddingRuntimeBridge()),
    ],
  );

  addTearDown(container.dispose);

  await container.read(modelDownloadControllerProvider).startDownload(
    entry: _embeddingEntry,
    source: _embeddingSourceA,
  );

  expect(downloadService.lastResumeFromBytes, 1024);
  expect(downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status, ModelDownloadStatus.completed);
});
```

- [ ] **Step 2: Write the failing application test for cold-start task reconciliation**

```dart
test('modelDownloadTasksProvider normalizes stale downloading task to paused using partial file bytes', () async {
  final downloadRepository = _MemoryDownloadRepository();
  final registryRepository = _MemoryRegistryRepository();
  final downloadService = _ResumeAwareFakeDownloadService(
    inspectTarget: const ModelDownloadTarget(
      localPath: '/models/embed-1.onnx',
      exists: true,
      existingBytes: 1536,
    ),
    result: const ModelDownloadResult(
      localPath: '/models/embed-1.onnx',
      totalBytes: 4096,
      verifiedChecksum: 'sha256:unused',
      resumed: false,
      fellBackToRestart: false,
      resumable: true,
    ),
  );

  downloadRepository.tasksById['task-1'] = buildTask(
    id: 'task-1',
    modelId: 'embed-1',
    sourceId: 'source-a',
    status: ModelDownloadStatus.downloading,
  );

  final container = ProviderContainer(
    overrides: [
      modelCatalogEntriesProvider.overrideWith((ref) async => const <ModelCatalogEntry>[_embeddingEntry]),
      modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
      modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
      modelDownloadServiceProvider.overrideWithValue(downloadService),
    ],
  );

  addTearDown(container.dispose);

  final tasks = await container.read(modelDownloadTasksProvider.future);

  expect(tasks.single.status, ModelDownloadStatus.paused);
  expect(tasks.single.downloadedBytes, 1536);
});
```

- [ ] **Step 3: Run the focused application tests to verify RED**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
```

Expected: FAIL because the provider/controller do not yet inspect partial files or reconcile stale tasks.

- [ ] **Step 4: Implement minimal controller/provider resume logic**

```dart
final modelDownloadTasksProvider = FutureProvider<List<ModelDownloadTask>>((ref) async {
  final tasks = await ref.watch(modelDownloadRepositoryProvider).listTasks();
  final catalog = await ref.watch(modelCatalogEntriesProvider.future);
  final service = ref.watch(modelDownloadServiceProvider);
  final resolved = <ModelDownloadTask>[];

  for (final task in tasks) {
    final entry = catalog.where((item) => item.id == task.modelId).firstOrNull;
    final source = entry?.sources.where((item) => item.id == task.sourceId).firstOrNull;
    if (entry == null || source == null) {
      resolved.add(task);
      continue;
    }

    final target = await service.inspectDownloadTarget(
      modelId: task.modelId,
      sourceUrl: source.url,
    );

    final hasPartialBytes = target.exists && target.existingBytes > 0;
    final shouldPauseRecoveredTask =
        hasPartialBytes && (task.status == ModelDownloadStatus.downloading || task.status == ModelDownloadStatus.queued);

    final normalized = task.copyWith(
      downloadedBytes: hasPartialBytes ? target.existingBytes : 0,
      status: shouldPauseRecoveredTask ? ModelDownloadStatus.paused : task.status,
      resumable: hasPartialBytes ? task.resumable : false,
    );

    if (normalized.downloadedBytes != task.downloadedBytes || normalized.status != task.status) {
      await ref.watch(modelDownloadRepositoryProvider).saveTask(normalized);
    }
    resolved.add(normalized);
  }

  return resolved;
});
```

```dart
final target = await _downloadService.inspectDownloadTarget(
  modelId: entry.id,
  sourceUrl: source.url,
);
final resumeFromBytes = target.exists ? target.existingBytes : 0;

await _repository.saveTask(
  task.copyWith(
    status: ModelDownloadStatus.downloading,
    downloadedBytes: resumeFromBytes,
    updatedAt: DateTime.now(),
  ),
);

final result = await _downloadService.download(
  taskId: task.id,
  modelId: entry.id,
  sourceUrl: source.url,
  expectedChecksum: source.checksum,
  resumeFromBytes: resumeFromBytes,
  onProgress: (progress) async {
    // keep existing update logic
  },
);
```

- [ ] **Step 5: Re-run the focused application tests to verify GREEN**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
```

Expected: PASS.

---

### Task 3: Surface resume-aware controls and copy in `ModelManagementPage`

**Files:**
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Write the failing widget test for the `继续下载` primary action**

```dart
testWidgets('ModelManagementPage shows 继续下载 for a paused resumable task', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelCatalogEntriesProvider.overrideWith((ref) async => const <ModelCatalogEntry>[_catalogEntry]),
        modelDownloadTasksProvider.overrideWith(
          (ref) async => <ModelDownloadTask>[
            ModelDownloadTask(
              id: 'task-1',
              modelId: 'embed-1',
              sourceId: 'src-1',
              status: ModelDownloadStatus.paused,
              totalBytes: 4096,
              downloadedBytes: 1024,
              averageSpeed: null,
              errorMessage: null,
              resumable: true,
              createdAt: DateTime(2026, 4, 30, 10, 0),
              updatedAt: DateTime(2026, 4, 30, 10, 1),
            ),
          ],
        ),
        modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
        activeModelSelectionProvider.overrideWith((ref) async => const ActiveModelSelection(activeEmbeddingModelId: null)),
        embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
        modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.widgetWithText(FilledButton, '继续下载'), findsOneWidget);
  expect(find.text('断点续传：支持'), findsOneWidget);
  expect(find.text('下载进度：25%'), findsOneWidget);
});
```

- [ ] **Step 2: Write the failing widget test for the `重试下载` fallback action**

```dart
testWidgets('ModelManagementPage keeps 重试下载 when failed task has no resumable bytes', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelCatalogEntriesProvider.overrideWith((ref) async => const <ModelCatalogEntry>[_catalogEntry]),
        modelDownloadTasksProvider.overrideWith(
          (ref) async => <ModelDownloadTask>[
            ModelDownloadTask(
              id: 'task-1',
              modelId: 'embed-1',
              sourceId: 'src-1',
              status: ModelDownloadStatus.failed,
              totalBytes: 4096,
              downloadedBytes: 0,
              averageSpeed: null,
              errorMessage: 'network error',
              resumable: false,
              createdAt: DateTime(2026, 4, 30, 10, 0),
              updatedAt: DateTime(2026, 4, 30, 10, 1),
            ),
          ],
        ),
        modelRegistryEntriesProvider.overrideWith((ref) async => const <ModelRegistryEntry>[]),
        activeModelSelectionProvider.overrideWith((ref) async => const ActiveModelSelection(activeEmbeddingModelId: null)),
        embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
        modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.widgetWithText(FilledButton, '开始下载'), findsNothing);
  expect(find.widgetWithText(OutlinedButton, '重试下载'), findsOneWidget);
});
```

- [ ] **Step 3: Run the widget tests to verify RED**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: FAIL because the page still uses a single `开始下载` primary label and does not derive resume-aware semantics.

- [ ] **Step 4: Implement minimal resume-aware UI semantics**

```dart
final hasPartialBytes = (latestTask?.downloadedBytes ?? 0) > 0;
final canResume = latestTask != null &&
    latestTask!.resumable &&
    hasPartialBytes &&
    (latestTask!.status == ModelDownloadStatus.paused ||
        latestTask!.status == ModelDownloadStatus.queued ||
        latestTask!.status == ModelDownloadStatus.failed);

final primaryDownloadLabel = isInstalled
    ? '已安装'
    : canResume
        ? '继续下载'
        : '开始下载';
```

```dart
FilledButton.tonalIcon(
  onPressed: selectedSource == null || isInstalled || isDownloading
      ? null
      : () => controller.startDownload(entry: entry, source: selectedSource),
  icon: const Icon(Icons.download_outlined),
  label: Text(primaryDownloadLabel),
)
```

```dart
Text('断点续传：${task!.resumable ? '支持' : '当前下载源不支持'}');
if (task!.progress != null) Text('下载进度：${(task!.progress! * 100).round()}%');
```

- [ ] **Step 5: Re-run the widget tests to verify GREEN**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: PASS.

---

### Task 4: Run focused verification for the whole Milestone 6-A slice

**Files:**
- Modify only if verification exposes a regression caused by Tasks 1-3.

- [ ] **Step 1: Run the focused model-management test suite**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/model_download_service_test.dart test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: no new errors introduced by the resume slice. If the repo still has a pre-existing non-blocking info, record it explicitly instead of claiming a clean run.

- [ ] **Step 3: Optional emulator sanity check if time permits**

Run:

```powershell
flutter run -d emulator-5556 --target lib/main.dart
```

Expected: app launches, `/models` page still renders, and a paused/resumable task can be inspected manually if local test setup is available.

---

## Self-Review

- Spec coverage: this plan covers pause/resume, restart recovery, partial-file progress recovery, fallback-to-full-download, and resume-aware UI copy.
- Placeholder scan: no TBD/TODO placeholders remain in the task steps.
- Type consistency: the plan keeps resume semantics inside `ModelDownloadService`, `ModelDownloadController`, and `ModelManagementPage`; no unrelated schema or provider family is introduced.

## Notes for the implementing worker

- Do **not** add automatic source switching in this plan.
- Do **not** add benchmark or device-tier logic in this plan.
- Do **not** create a new database table unless implementation proves the current task table is fundamentally insufficient.
- Do **not** create git commits unless the user explicitly requests them.
