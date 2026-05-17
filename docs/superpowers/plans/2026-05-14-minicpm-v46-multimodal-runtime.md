# MiniCPM-V 4.6 Multimodal Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real MiniCPM-V 4.6 local deployment and local image+prompt multimodal inference support without pretending it is a normal text-only LLM.

**Architecture:** Keep `multimodal_llm` as a first-class model type. Extend catalog/registry/download code to support multiple required artifacts per model, then add a separate multimodal bridge/runtime path that passes `modelPath`, `mmprojPath`, `imagePath`, and `reasoningEnabled=false` to Android. Native support is implemented behind a `MultimodalLlmRuntimeContract`; if the current llama.cpp AAR lacks mtmd APIs, the runtime must fail with an explicit “native runtime unavailable” error until the mtmd backend is added.

**Tech Stack:** Flutter/Dart, Riverpod, sqflite_sqlcipher, MethodChannel, Kotlin/JUnit, Android llama.cpp/mtmd native backend, existing model catalog JSON.

---

## File Structure

### Create

- `lib/features/ai_models/domain/model_artifact_path.dart` — immutable registry artifact path value (`role`, `sourceId`, `localPath`, `checksum`, `sizeBytes`).
- `lib/features/ai_chat/domain/multimodal_llm_engine.dart` — request/result/domain interface for image+prompt local generation.
- `lib/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart` — Dart MethodChannel bridge for `ensureMultimodalModelReady` and `generateMultimodalText`.
- `lib/features/ai_chat/application/multimodal_llm_runtime_providers.dart` — Riverpod providers for the new bridge.
- `android/app/src/main/kotlin/com/example/note_secret_search/MultimodalLlmRuntime.kt` — Kotlin runtime contract, model spec, and fallback implementation.
- `android/app/src/test/kotlin/com/example/note_secret_search/MultimodalLlmRuntimeTest.kt` — missing-mmproj and unavailable-native tests.
- `test/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge_test.dart` — MethodChannel payload tests.

### Modify

- `assets/model_catalog/built_in_catalog.json` — change MiniCPM-V tier/recommended tier/runtime metadata from unsupported to deployable multimodal runtime.
- `lib/features/ai_models/domain/model_catalog_entry.dart` — add source `role` and `required` parsing, keeping backward compatibility.
- `lib/features/ai_models/domain/model_registry_entry.dart` — add `artifacts` while preserving `localPath` as the primary model path.
- `lib/core/storage/database/database_schema.dart` — add `artifact_paths_json` to `model_registry`.
- `lib/features/ai_models/infrastructure/sqlite_model_registry_repository.dart` — persist and read `artifact_paths_json`.
- `lib/features/ai_models/infrastructure/model_download_service.dart` — make target file names source-aware so the MiniCPM model and mmproj do not overwrite each other.
- `lib/features/ai_models/application/model_download_providers.dart` — add multimodal download support, multi-artifact aggregation, registry artifact saving, and runtime readiness check.
- `lib/features/ai_models/presentation/model_presentation_formatter.dart` — allow `multimodal_llm` downloads and show deployable multimodal status.
- `lib/features/ai_models/presentation/model_management_page.dart` — surface per-artifact status and enable MiniCPM download.
- `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart` — leave text methods compatible; do not add image fields here.
- `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt` — add multimodal method handlers while preserving existing text handlers.
- Existing Dart and Kotlin tests under `test/features/ai_models/**` and `android/app/src/test/**` — update expectations from “reject multimodal” to “downloads all required artifacts / explicit runtime unavailable if native is missing”.

---

### Task 1: Catalog artifact roles and deployable MiniCPM metadata

**Files:**
- Modify: `lib/features/ai_models/domain/model_catalog_entry.dart`
- Modify: `assets/model_catalog/built_in_catalog.json`
- Test: `test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`

- [ ] **Step 1: Write failing catalog parsing tests**

Add assertions to the existing MiniCPM catalog test in `test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`:

```dart
final minicpm = entries.singleWhere((entry) => entry.id == 'minicpm_v_4_6_q4_k_m');
expect(minicpm.type, 'multimodal_llm');
expect(minicpm.tier, 'local_multimodal');
expect(minicpm.recommendedTier, 'vision_language_local');
expect(minicpm.sources, hasLength(2));
expect(minicpm.sources.map((source) => source.role), containsAll(<String>['model', 'mmproj']));
expect(minicpm.sources.every((source) => source.required), isTrue);
```

- [ ] **Step 2: Run the catalog test and verify it fails**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart
```

Expected: FAIL because `ModelSourceEntry.role` and `ModelSourceEntry.required` do not exist, and catalog still has unsupported tier metadata.

- [ ] **Step 3: Extend `ModelSourceEntry`**

In `lib/features/ai_models/domain/model_catalog_entry.dart`, update `ModelSourceEntry`:

```dart
class ModelSourceEntry {
  const ModelSourceEntry({
    required this.id,
    required this.label,
    required this.url,
    this.checksum = '',
    this.role = 'model',
    this.required = true,
    this.signature,
    this.signatureAlgorithm,
    this.keyId,
  });

  factory ModelSourceEntry.fromJson(Map<String, dynamic> json) {
    return ModelSourceEntry(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      url: json['url'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
      role: json['role'] as String? ?? 'model',
      required: json['required'] as bool? ?? true,
      signature: json['signature'] as String?,
      signatureAlgorithm: (json['signature_algorithm'] ?? json['signatureAlgorithm']) as String?,
      keyId: (json['key_id'] ?? json['keyId']) as String?,
    );
  }

  bool declaresArtifactTrust() {
    return signature != null && signatureAlgorithm != null;
  }

  final String id;
  final String label;
  final String url;
  final String checksum;
  final String role;
  final bool required;
  final String? signature;
  final String? signatureAlgorithm;
  final String? keyId;
}
```

- [ ] **Step 4: Update MiniCPM catalog entry**

In `assets/model_catalog/built_in_catalog.json`, update only the MiniCPM entry:

```json
"type": "multimodal_llm",
"tier": "local_multimodal",
"recommended_tier": "vision_language_local",
"runtime": {
  "backend": "llama_cpp_mtmd",
  "variant": "minicpm_v4_6",
  "reasoning": "off"
}
```

For the source entries, add roles and required flags:

```json
{
  "id": "minicpm-v-4-6-q4-k-m-llm",
  "label": "MiniCPM-V 4.6 Q4_K_M 主模型",
  "role": "model",
  "required": true,
  "url": "https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/MiniCPM-V-4_6-Q4_K_M.gguf",
  "checksum": "sha256:..."
}
```

```json
{
  "id": "minicpm-v-4-6-mmproj-f16",
  "label": "MiniCPM-V 4.6 mmproj F16 视觉投影",
  "role": "mmproj",
  "required": true,
  "url": "https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/mmproj-model-f16.gguf",
  "checksum": "sha256:..."
}
```

Keep existing checksum values if already present. If a checksum is unavailable, leave the existing empty value and expect current checksum validation to fail until official checksum is added; do not invent a checksum.

- [ ] **Step 5: Run catalog test and verify it passes**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart
```

Expected: PASS.

---

### Task 2: Registry artifact persistence

**Files:**
- Create: `lib/features/ai_models/domain/model_artifact_path.dart`
- Modify: `lib/features/ai_models/domain/model_registry_entry.dart`
- Modify: `lib/core/storage/database/database_schema.dart`
- Modify: `lib/features/ai_models/infrastructure/sqlite_model_registry_repository.dart`
- Test: existing registry repository tests, or create `test/features/ai_models/infrastructure/sqlite_model_registry_repository_test.dart` if none exists.

- [ ] **Step 1: Add failing domain test for installed multimodal entries**

Create or extend a domain test with this case:

```dart
test('multimodal registry entry is installed only when required artifacts exist', () {
  final entry = ModelRegistryEntry(
    id: 'minicpm_v_4_6_q4_k_m',
    type: 'multimodal_llm',
    provider: 'builtin_catalog',
    name: 'MiniCPM-V 4.6',
    version: null,
    sizeBytes: 1516275776,
    quantization: 'Q4_K_M',
    minRamMb: 6144,
    recommendedTier: 'vision_language_local',
    localPath: '/models/MiniCPM-V-4_6-Q4_K_M.gguf',
    checksum: 'sha256:model',
    enabled: true,
    installedAt: DateTime.fromMillisecondsSinceEpoch(1),
    filePresent: true,
    integrityStatus: ModelIntegrityStatus.valid,
    artifacts: const <ModelArtifactPath>[
      ModelArtifactPath(role: 'model', sourceId: 'model-source', localPath: '/models/MiniCPM-V-4_6-Q4_K_M.gguf', checksum: 'sha256:model', sizeBytes: 1),
      ModelArtifactPath(role: 'mmproj', sourceId: 'mmproj-source', localPath: '/models/mmproj-model-f16.gguf', checksum: 'sha256:mmproj', sizeBytes: 2),
    ],
  );

  expect(entry.artifactPathForRole('mmproj'), '/models/mmproj-model-f16.gguf');
  expect(entry.isInstalled, isTrue);
});
```

- [ ] **Step 2: Run the new test and verify it fails**

Run the exact test file you created or modified:

```powershell
flutter test test/features/ai_models/domain/model_registry_entry_test.dart
```

Expected: FAIL because `ModelArtifactPath`, `artifacts`, and `artifactPathForRole` do not exist.

- [ ] **Step 3: Create artifact value object**

Create `lib/features/ai_models/domain/model_artifact_path.dart`:

```dart
class ModelArtifactPath {
  const ModelArtifactPath({
    required this.role,
    required this.sourceId,
    required this.localPath,
    this.checksum,
    this.sizeBytes,
  });

  factory ModelArtifactPath.fromJson(Map<String, dynamic> json) {
    return ModelArtifactPath(
      role: json['role'] as String? ?? 'model',
      sourceId: json['source_id'] as String? ?? '',
      localPath: json['local_path'] as String? ?? '',
      checksum: json['checksum'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
    );
  }

  final String role;
  final String sourceId;
  final String localPath;
  final String? checksum;
  final int? sizeBytes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'role': role,
      'source_id': sourceId,
      'local_path': localPath,
      'checksum': checksum,
      'size_bytes': sizeBytes,
    };
  }
}
```

- [ ] **Step 4: Extend `ModelRegistryEntry`**

Modify `lib/features/ai_models/domain/model_registry_entry.dart`:

```dart
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
```

Add constructor field:

```dart
this.artifacts = const <ModelArtifactPath>[],
```

Add class field:

```dart
final List<ModelArtifactPath> artifacts;
```

Update `isInstalled`:

```dart
bool get isInstalled {
  final hasPrimaryPath = localPath?.isNotEmpty ?? false;
  final hasRequiredMultimodalArtifacts = type != 'multimodal_llm' ||
      (artifactPathForRole('model') != null && artifactPathForRole('mmproj') != null);
  return enabled &&
      filePresent &&
      integrityStatus != ModelIntegrityStatus.corrupted &&
      hasPrimaryPath &&
      hasRequiredMultimodalArtifacts;
}

String? artifactPathForRole(String role) {
  for (final artifact in artifacts) {
    if (artifact.role == role && artifact.localPath.isNotEmpty) {
      return artifact.localPath;
    }
  }
  return null;
}
```

Update `copyWith` to accept `List<ModelArtifactPath>? artifacts` and pass `artifacts: artifacts ?? this.artifacts`.

- [ ] **Step 5: Persist artifacts JSON in SQLite**

Modify `lib/core/storage/database/database_schema.dart` model registry create statement:

```sql
artifact_paths_json TEXT,
```

Place it after `local_path TEXT,`.

Modify `lib/features/ai_models/infrastructure/sqlite_model_registry_repository.dart` to import `dart:convert` and `model_artifact_path.dart`. In `save`, add:

```dart
'artifact_paths_json': jsonEncode(entry.artifacts.map((artifact) => artifact.toJson()).toList(growable: false)),
```

In `_mapEntry`, add:

```dart
artifacts: _parseArtifacts(row['artifact_paths_json'] as String?),
```

Add helper:

```dart
List<ModelArtifactPath> _parseArtifacts(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <ModelArtifactPath>[];
  }
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    return const <ModelArtifactPath>[];
  }
  return decoded
      .whereType<Map<String, dynamic>>()
      .map(ModelArtifactPath.fromJson)
      .toList(growable: false);
}
```

- [ ] **Step 6: Run registry/domain tests**

Run:

```powershell
flutter test test/features/ai_models/domain/model_registry_entry_test.dart
```

Expected: PASS.

---

### Task 3: Source-aware file targets for multi-artifact downloads

**Files:**
- Modify: `lib/features/ai_models/infrastructure/model_download_service.dart`
- Test: `test/features/ai_models/infrastructure/model_download_service_test.dart`

- [ ] **Step 1: Write failing target naming test**

Add a test that calls `inspectDownloadTarget` twice for the same `modelId` with MiniCPM model and mmproj URLs:

```dart
test('inspectDownloadTarget uses source-specific filenames for multimodal artifacts', () async {
  final tempDir = await Directory.systemTemp.createTemp('model-target-test');
  addTearDown(() => tempDir.delete(recursive: true));
  final service = ModelDownloadService(
    dio: Dio(),
    logger: const AppLogger(),
    applicationSupportDirectoryProvider: () async => tempDir,
  );

  final modelTarget = await service.inspectDownloadTarget(
    modelId: 'minicpm_v_4_6_q4_k_m',
    sourceUrl: 'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/MiniCPM-V-4_6-Q4_K_M.gguf',
  );
  final mmprojTarget = await service.inspectDownloadTarget(
    modelId: 'minicpm_v_4_6_q4_k_m',
    sourceUrl: 'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/mmproj-model-f16.gguf',
  );

  expect(modelTarget.localPath, isNot(mmprojTarget.localPath));
  expect(modelTarget.localPath, contains('MiniCPM-V-4_6-Q4_K_M.gguf'));
  expect(mmprojTarget.localPath, contains('mmproj-model-f16.gguf'));
});
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/model_download_service_test.dart
```

Expected: FAIL because both targets resolve to `minicpm_v_4_6_q4_k_m.gguf`.

- [ ] **Step 3: Implement source-aware target naming**

Replace `_resolveTargetFile` in `model_download_service.dart` with source filename preserving logic:

```dart
Future<File> _resolveTargetFile(String modelId, String sourceUrl) async {
  final appDir = await _applicationSupportDirectoryProvider();
  final modelDir = Directory(p.join(appDir.path, 'models', modelId));
  if (!await modelDir.exists()) {
    await modelDir.create(recursive: true);
  }

  final uri = Uri.parse(sourceUrl);
  final rawFileName = p.basename(uri.path);
  final safeFileName = _sanitizeFileName(rawFileName.isEmpty ? '$modelId.bin' : rawFileName);
  return File(p.join(modelDir.path, safeFileName));
}

String _sanitizeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return sanitized.isEmpty ? 'artifact.bin' : sanitized;
}
```

- [ ] **Step 4: Run download service tests**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/model_download_service_test.dart
```

Expected: PASS.

---

### Task 4: Enable multimodal download aggregation and registry saving

**Files:**
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
- Modify: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- Test: `test/features/ai_models/application/model_download_providers_test.dart`
- Test: `test/features/ai_models/presentation/model_presentation_formatter_test.dart`

- [ ] **Step 1: Replace rejection test with multi-artifact acceptance test**

In `model_download_providers_test.dart`, replace `startDownload rejects multimodal llm catalog entries until runtime is supported` with:

```dart
test('startDownload downloads all required multimodal artifacts before saving registry entry', () async {
  final downloadRepository = _MemoryDownloadRepository();
  final registryRepository = _MemoryRegistryRepository();
  final downloadService = _FakeDownloadService();
  const modelUrl = 'https://example.com/MiniCPM-V-4_6-Q4_K_M.gguf';
  const mmprojUrl = 'https://example.com/mmproj-model-f16.gguf';
  downloadService.setResultForSource(
    sourceUrl: modelUrl,
    result: const ModelDownloadResult(
      localPath: '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf',
      totalBytes: 10,
      verifiedChecksum: 'sha256:model',
    ),
  );
  downloadService.setResultForSource(
    sourceUrl: mmprojUrl,
    result: const ModelDownloadResult(
      localPath: '/models/minicpm/mmproj-model-f16.gguf',
      totalBytes: 20,
      verifiedChecksum: 'sha256:mmproj',
    ),
  );

  final entry = ModelCatalogEntry(
    id: 'minicpm_v_4_6_q4_k_m',
    type: 'multimodal_llm',
    tier: 'local_multimodal',
    displayName: 'MiniCPM-V 4.6',
    description: 'Vision-language local model',
    sizeBytes: 30,
    minRamMb: 6144,
    recommendedTier: 'vision_language_local',
    sources: const <ModelSourceEntry>[
      ModelSourceEntry(id: 'model-source', label: 'model', role: 'model', url: modelUrl, checksum: 'sha256:model'),
      ModelSourceEntry(id: 'mmproj-source', label: 'mmproj', role: 'mmproj', url: mmprojUrl, checksum: 'sha256:mmproj'),
    ],
  );

  final container = _createContainer(
    downloadRepository: downloadRepository,
    registryRepository: registryRepository,
    catalogRepository: _MemoryCatalogRepository(<ModelCatalogEntry>[entry]),
    downloadService: downloadService,
  );
  addTearDown(container.dispose);

  await container.read(modelDownloadControllerProvider.notifier).startDownload(
        entry: entry,
        source: entry.sources.first,
      );

  expect(downloadService.invocations.map((item) => item.sourceUrl), containsAll(<String>[modelUrl, mmprojUrl]));
  final saved = registryRepository.entries['minicpm_v_4_6_q4_k_m'];
  expect(saved, isNotNull);
  expect(saved!.localPath, '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf');
  expect(saved.artifactPathForRole('mmproj'), '/models/minicpm/mmproj-model-f16.gguf');
  expect(saved.isInstalled, isTrue);
});
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
```

Expected: FAIL because multimodal downloads are rejected and no artifact aggregation exists.

- [ ] **Step 3: Allow multimodal download support in formatter and controller**

In `model_presentation_formatter.dart`:

```dart
bool isCatalogEntryDownloadSupported(ModelCatalogEntry entry) {
  return entry.type == 'embedding' || entry.type == 'llm' || entry.type == 'multimodal_llm';
}
```

Update runtime support status for `multimodal_llm` to say:

```dart
return '需要下载主模型和视觉投影文件，部署后可进行本地多模态推理。';
```

In `model_download_providers.dart`:

```dart
bool _isDownloadRuntimeSupported(ModelCatalogEntry entry) {
  return entry.type == 'embedding' || entry.type == 'llm' || entry.type == 'multimodal_llm';
}
```

- [ ] **Step 4: Add multimodal download branch**

At the start of `startDownload`, after existing registry cleanup and before single-source candidate ordering, route multimodal entries:

```dart
if (entry.type == 'multimodal_llm') {
  await _startMultimodalDownload(entry: entry);
  return;
}
```

Add helper:

```dart
Future<void> _startMultimodalDownload({required ModelCatalogEntry entry}) async {
  final requiredSources = entry.sources.where((source) => source.required).toList(growable: false);
  final results = <ModelSourceEntry, ModelDownloadResult>{};

  for (final source in requiredSources) {
    await enqueueDownload(modelId: entry.id, sourceId: source.id, totalBytes: null);
    final task = await _repository.findLatestTaskByModelAndSource(entry.id, source.id);
    if (task == null) {
      continue;
    }
    await _repository.saveTask(task.copyWith(status: ModelDownloadStatus.downloading, updatedAt: DateTime.now()));
    try {
      final result = await _downloadService.download(
        taskId: task.id,
        modelId: entry.id,
        sourceUrl: source.url,
        expectedChecksum: source.checksum,
        onProgress: (progress) async {
          final current = await _repository.findLatestTaskByModelAndSource(entry.id, source.id);
          if (current == null) {
            return;
          }
          await _repository.saveTask(
            current.copyWith(
              status: ModelDownloadStatus.downloading,
              totalBytes: progress.totalBytes ?? current.totalBytes,
              downloadedBytes: progress.receivedBytes,
              averageSpeed: progress.averageSpeedBytesPerSecond,
              clearErrorMessage: true,
              updatedAt: DateTime.now(),
            ),
          );
        },
      );
      results[source] = result;
      await _repository.saveTask(
        task.copyWith(
          status: ModelDownloadStatus.completed,
          downloadedBytes: result.totalBytes,
          totalBytes: result.totalBytes,
          clearErrorMessage: true,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      await markFailedForSource(entry.id, sourceId: source.id, message: error.toString());
      return;
    }
  }

  await _completeSuccessfulMultimodalDownload(entry: entry, results: results);
}
```

Add `_completeSuccessfulMultimodalDownload` to create `ModelArtifactPath` list, choose role `model` as primary `localPath`, save registry, then call multimodal readiness provider in a later task. For now set `enabled: true`, `filePresent: true`, `integrityStatus: ModelIntegrityStatus.valid` only when both `model` and `mmproj` artifact paths exist.

- [ ] **Step 5: Run model download tests**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart
```

Expected: PASS after updating obsolete rejection expectations.

---

### Task 5: Dart multimodal MethodChannel bridge

**Files:**
- Create: `lib/features/ai_chat/domain/multimodal_llm_engine.dart`
- Create: `lib/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart`
- Create: `lib/features/ai_chat/application/multimodal_llm_runtime_providers.dart`
- Test: `test/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge_test.dart`

- [ ] **Step 1: Write failing bridge payload test**

Create `test/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generateMultimodalText sends model mmproj image and reasoning off', () async {
    const channel = MethodChannel('test/multimodal_llm_runtime');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'status': 'ready', 'text': 'A cat', 'finishReason': 'stop'};
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    final bridge = MethodChannelMultimodalLlmRuntimeBridge(channel: channel);
    final result = await bridge.generateMultimodalText(
      modelId: 'minicpm_v_4_6_q4_k_m',
      modelPath: '/models/model.gguf',
      mmprojPath: '/models/mmproj-model-f16.gguf',
      imagePath: '/cache/input.jpg',
      prompt: 'Describe it',
      maxOutputTokens: 96,
      contextLength: 1024,
      reasoningEnabled: false,
    );

    expect(result['text'], 'A cat');
    expect(calls.single.method, 'generateMultimodalText');
    expect(calls.single.arguments, containsPair('mmprojPath', '/models/mmproj-model-f16.gguf'));
    expect(calls.single.arguments, containsPair('imagePath', '/cache/input.jpg'));
    expect(calls.single.arguments, containsPair('reasoningEnabled', false));
  });
}
```

- [ ] **Step 2: Run bridge test and verify it fails**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge_test.dart
```

Expected: FAIL because bridge file does not exist.

- [ ] **Step 3: Create domain and bridge files**

Create `lib/features/ai_chat/domain/multimodal_llm_engine.dart`:

```dart
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

class MultimodalLlmInferenceRequest {
  const MultimodalLlmInferenceRequest({
    required this.model,
    required this.prompt,
    required this.imagePath,
    this.maxOutputTokens = 96,
    this.contextLength = 1024,
    this.reasoningEnabled = false,
  });

  final ModelRegistryEntry model;
  final String prompt;
  final String imagePath;
  final int maxOutputTokens;
  final int contextLength;
  final bool reasoningEnabled;
}
```

Create `lib/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart` with interface and MethodChannel implementation matching the test.

Create provider file:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart';

final multimodalLlmRuntimeBridgeProvider = Provider<MultimodalLlmRuntimeBridge>((ref) {
  return MethodChannelMultimodalLlmRuntimeBridge();
});
```

- [ ] **Step 4: Run bridge test**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge_test.dart
```

Expected: PASS.

---

### Task 6: Kotlin multimodal plugin contract and explicit native-unavailable behavior

**Files:**
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/MultimodalLlmRuntime.kt`
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt`
- Create: `android/app/src/test/kotlin/com/example/note_secret_search/MultimodalLlmRuntimeTest.kt`
- Modify: `android/app/src/test/kotlin/com/example/note_secret_search/LlmRuntimePluginTest.kt`

- [ ] **Step 1: Write failing Kotlin runtime tests**

Create `MultimodalLlmRuntimeTest.kt`:

```kotlin
package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class MultimodalLlmRuntimeTest {
    @Test
    fun `ensure model ready reports missing mmproj`() {
        val runtime = FallbackMultimodalLlmRuntime()
        val payload = runtime.ensureModelReady(
            modelId = "minicpm_v_4_6_q4_k_m",
            modelPath = "/models/model.gguf",
            mmprojPath = "",
        )

        assertEquals("missing_mmproj", payload["status"])
        assertEquals(false, payload["ready"])
    }

    @Test
    fun `generate reports native runtime unavailable before mtmd backend is installed`() {
        val runtime = FallbackMultimodalLlmRuntime()
        val payload = runtime.generateMultimodalText(
            modelId = "minicpm_v_4_6_q4_k_m",
            modelPath = "/models/model.gguf",
            mmprojPath = "/models/mmproj.gguf",
            imagePath = "/cache/input.jpg",
            prompt = "Describe it",
            config = LocalLlmGenerationConfig(),
            reasoningEnabled = false,
        )

        assertEquals("runtime_unavailable", payload["status"])
        assertFalse(payload["ready"] as Boolean)
    }
}
```

- [ ] **Step 2: Run Kotlin test and verify it fails**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "com.example.note_secret_search.MultimodalLlmRuntimeTest"
```

Expected: FAIL because runtime file does not exist.

- [ ] **Step 3: Implement fallback runtime contract**

Create `MultimodalLlmRuntime.kt`:

```kotlin
package com.example.note_secret_search

interface MultimodalLlmRuntimeContract {
    fun ensureModelReady(modelId: String, modelPath: String, mmprojPath: String): Map<String, Any?>

    fun generateMultimodalText(
        modelId: String,
        modelPath: String,
        mmprojPath: String,
        imagePath: String,
        prompt: String,
        config: LocalLlmGenerationConfig,
        reasoningEnabled: Boolean,
    ): Map<String, Any?>
}

class FallbackMultimodalLlmRuntime : MultimodalLlmRuntimeContract {
    override fun ensureModelReady(modelId: String, modelPath: String, mmprojPath: String): Map<String, Any?> {
        if (mmprojPath.isBlank()) {
            return mapOf(
                "status" to "missing_mmproj",
                "ready" to false,
                "message" to "MiniCPM-V 视觉投影文件缺失，请重新下载。",
            )
        }
        return mapOf(
            "status" to "runtime_unavailable",
            "ready" to false,
            "message" to "当前 native runtime 不支持 MiniCPM-V 4.6 多模态推理，请更新 runtime。",
        )
    }

    override fun generateMultimodalText(
        modelId: String,
        modelPath: String,
        mmprojPath: String,
        imagePath: String,
        prompt: String,
        config: LocalLlmGenerationConfig,
        reasoningEnabled: Boolean,
    ): Map<String, Any?> {
        return ensureModelReady(modelId = modelId, modelPath = modelPath, mmprojPath = mmprojPath)
    }
}
```

- [ ] **Step 4: Add plugin method handlers**

Modify `LlmRuntimePlugin` constructor to include:

```kotlin
private val multimodalRuntime: MultimodalLlmRuntimeContract = FallbackMultimodalLlmRuntime(),
```

Add `ensureMultimodalModelReady` and `generateMultimodalText` branches in `onMethodCall`. Both must use `requiredString` for `modelId`, `modelPath`, `mmprojPath`; generation also requires `imagePath` and `prompt`. `reasoningEnabled` defaults to `false`.

- [ ] **Step 5: Run Kotlin plugin/runtime tests**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "com.example.note_secret_search.MultimodalLlmRuntimeTest"
.\gradlew.bat :app:testDebugUnitTest --tests "com.example.note_secret_search.LlmRuntimePluginTest"
```

Expected: PASS.

---

### Task 7: Wire multimodal readiness into download completion

**Files:**
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
- Modify: `lib/features/ai_chat/application/multimodal_llm_runtime_providers.dart`
- Test: `test/features/ai_models/application/model_download_providers_test.dart`

- [ ] **Step 1: Write failing test for runtime unavailable after files are deployed**

Extend the Task 4 acceptance test to override `multimodalLlmRuntimeBridgeProvider` with a fake returning:

```dart
<String, dynamic>{
  'status': 'runtime_unavailable',
  'ready': false,
  'message': '当前 native runtime 不支持 MiniCPM-V 4.6 多模态推理，请更新 runtime。',
}
```

Assert registry keeps artifact paths but `enabled` is `false`:

```dart
expect(saved!.artifactPathForRole('mmproj'), '/models/minicpm/mmproj-model-f16.gguf');
expect(saved.enabled, isFalse);
expect(saved.isInstalled, isFalse);
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
```

Expected: FAIL because completion does not call multimodal runtime readiness.

- [ ] **Step 3: Call multimodal readiness bridge after artifact save**

In `_completeSuccessfulMultimodalDownload`, after saving registry, call:

```dart
final runtimeResult = await _ref.read(multimodalLlmRuntimeBridgeProvider).ensureModelReady(
  modelId: entry.id,
  modelPath: modelArtifact.localPath,
  mmprojPath: mmprojArtifact.localPath,
);
final ready = runtimeResult['ready'] == true;
final persisted = await _registryRepository.getById(entry.id);
if (persisted != null) {
  await _registryRepository.save(
    persisted.copyWith(
      enabled: ready,
      filePresent: true,
    ),
  );
}
```

Do not delete artifact paths when runtime is unavailable; files are deployed but not yet inferable.

- [ ] **Step 4: Run model download tests**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
```

Expected: PASS.

---

### Task 8: Add UI affordance for multimodal deployment status

**Files:**
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- Test: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Write failing UI test**

Add or update a widget test that renders MiniCPM-V and expects:

```dart
expect(find.textContaining('主模型'), findsOneWidget);
expect(find.textContaining('视觉投影'), findsOneWidget);
expect(find.textContaining('本地多模态推理'), findsOneWidget);
expect(find.widgetWithText(FilledButton, '下载'), findsOneWidget);
```

- [ ] **Step 2: Run UI test and verify it fails**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: FAIL because current UI still treats unsupported runtime specially.

- [ ] **Step 3: Update model card copy**

In `model_management_page.dart`, when `entry.type == 'multimodal_llm'`, render a compact artifact list:

```dart
for (final source in entry.sources.where((source) => source.required))
  Text('${source.role == 'mmproj' ? '视觉投影' : '主模型'}：${source.label}')
```

Keep the existing button enablement but let `isCatalogEntryDownloadSupported` decide support.

- [ ] **Step 4: Run UI tests**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: PASS.

---

### Task 9: Native mtmd backend integration spike and replacement point

**Files:**
- Modify or create native backend files after inspecting AAR/API.
- Test: `android/app/src/test/kotlin/com/example/note_secret_search/MultimodalLlmRuntimeTest.kt`
- Docs: update `docs/superpowers/specs/2026-05-14-minicpm-v46-multimodal-runtime-design.md` if the chosen backend differs from the spec options.

- [ ] **Step 1: Inspect current AAR for multimodal APIs**

Run:

```powershell
.\gradlew.bat :app:dependencies --configuration debugRuntimeClasspath
```

Then inspect `android/third_party/llamacpp-kotlin-0.2.0-huawei-safe.aar` with archive tools. Look for classes or native symbols that expose `mmproj`, `image`, `mtmd`, or `multimodal`.

Expected: Current AAR likely only exposes `LlamaHelper.load(path, contextLength, callback)`.

- [ ] **Step 2: If no mtmd API exists, add explicit backend replacement issue in code**

Keep `FallbackMultimodalLlmRuntime` as the app-facing behavior and add a Kotlin comment above it:

```kotlin
// This fallback is intentionally not a success path. Replace it with a llama.cpp mtmd backend
// that accepts modelPath, mmprojPath, imagePath, and reasoningEnabled=false for MiniCPM-V 4.6.
```

Do not claim full MiniCPM inference support until the native backend is replaced and true device inference passes.

- [ ] **Step 3: Implement real backend when mtmd API is available**

Replace `FallbackMultimodalLlmRuntime` injection with a real runtime that:

1. Verifies `modelPath`, `mmprojPath`, and `imagePath` exist.
2. Loads model with mmproj.
3. Sends image and prompt.
4. Forces `reasoningEnabled=false` for MiniCPM-V 4.6 Instruct.
5. Returns non-empty `text` or throws `IllegalStateException("Backend returned empty multimodal text.")`.

- [ ] **Step 4: Run Kotlin tests**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "com.example.note_secret_search.MultimodalLlmRuntimeTest"
```

Expected: PASS for fallback behavior until real backend exists; after backend exists, add a fake backend unit test for successful image response.

---

### Task 10: Verification and APK export

**Files:**
- Output: `E:\Archive\Flutter\note_secret_search\app-debug.apk`

- [ ] **Step 1: Run focused Dart tests**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart
flutter test test/features/ai_models/domain/model_registry_entry_test.dart
flutter test test/features/ai_models/infrastructure/model_download_service_test.dart
flutter test test/features/ai_models/application/model_download_providers_test.dart
flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart
flutter test test/features/ai_models/presentation/model_management_page_test.dart
flutter test test/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge_test.dart
```

Expected: all PASS.

- [ ] **Step 2: Run Kotlin unit tests**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests "com.example.note_secret_search.MultimodalLlmRuntimeTest"
.\gradlew.bat :app:testDebugUnitTest --tests "com.example.note_secret_search.LlmRuntimePluginTest"
.\gradlew.bat :app:testDebugUnitTest --tests "com.example.note_secret_search.GgufLlamaCppBackendTest"
```

Expected: all PASS.

- [ ] **Step 3: Run analyzer**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Build APK**

Run:

```powershell
flutter build apk --debug
```

Expected: build succeeds.

- [ ] **Step 5: Export APK to project root**

Run:

```powershell
Copy-Item -LiteralPath "build\app\outputs\flutter-apk\app-debug.apk" -Destination "app-debug.apk" -Force
```

Expected: `E:\Archive\Flutter\note_secret_search\app-debug.apk` exists.

- [ ] **Step 6: True device multimodal acceptance**

Run on connected Huawei `SPN_AL00` or equivalent:

```powershell
adb -s H8B4C19731000256 install -r "app-debug.apk"
adb -s H8B4C19731000256 shell run-as com.example.note_secret_search ls -la files/models/minicpm_v_4_6_q4_k_m
```

Expected before native backend replacement: files can deploy, but runtime readiness reports explicit native unavailable. Expected final acceptance after native backend replacement: app sends image+prompt and UI shows non-empty local multimodal reply with no `SIGABRT`, no `Backend returned empty text`, and no runtime unsupported error.

---

## Self-Review

- Spec coverage: The plan covers catalog, multi-artifact registry, download aggregation, Dart bridge, Kotlin plugin/runtime, UI, verification, and true device acceptance. Native backend replacement is explicitly isolated because the current AAR likely lacks mtmd APIs.
- Placeholder scan: No task uses “TBD” or asks for generic “handle edge cases” without concrete behavior. The only conditional work is native backend replacement, which depends on actual AAR/API capability and has explicit fallback behavior that must not be treated as final success.
- Type consistency: `ModelArtifactPath`, `artifacts`, `artifactPathForRole`, `MultimodalLlmRuntimeBridge`, `ensureMultimodalModelReady`, and `generateMultimodalText` are introduced before later tasks use them.
