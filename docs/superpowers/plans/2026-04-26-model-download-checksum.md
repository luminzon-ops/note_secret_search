# Model Download Checksum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Phase 1 model download management by verifying downloaded model files against catalog-provided checksums before treating them as installed.

**Architecture:** Extend the catalog source metadata to carry checksum information, then make the download service compute and validate the downloaded file digest before the controller marks the task completed or writes a usable registry record. Keep the slice narrow: no resume, no failover, no signature verification, and no provider work.

**Tech Stack:** Flutter, Dart IO streams, Dio, Riverpod, Flutter test

---

## File Structure

- Modify: `lib/features/ai_models/domain/model_catalog_entry.dart`
  - Add checksum metadata to `ModelSourceEntry` and parse it from JSON.
- Modify: `assets/model_catalog/built_in_catalog.json`
  - Add checksum field to the built-in model source entry.
- Modify: `lib/features/ai_models/infrastructure/model_download_service.dart`
  - Add file checksum calculation + verification APIs.
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
  - Enforce checksum verification before marking a download complete and persist checksum on success.
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`
  - Add success/failure verification path coverage.
- Create: `test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`
  - Add catalog parsing coverage for checksum metadata.

### Task 1: Catalog checksum metadata

**Files:**
- Modify: `lib/features/ai_models/domain/model_catalog_entry.dart`
- Modify: `assets/model_catalog/built_in_catalog.json`
- Create: `test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`

- [ ] **Step 1: Write the failing catalog parsing test**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/asset_model_catalog_repository.dart';

void main() {
  test('loadCatalog parses checksum metadata from source_list', () async {
    final repository = AssetModelCatalogRepository(
      assetBundle: _FakeAssetBundle('''
[
  {
    "id": "embed_min_cn_v1",
    "type": "embedding",
    "tier": "minimum",
    "display_name": "内置最小版 Embedding",
    "description": "低端设备优先，MVP 默认推荐。",
    "size_bytes": 157286400,
    "min_ram_mb": 3072,
    "recommended_tier": "tier_1",
    "source_list": [
      {
        "id": "official-cn",
        "label": "国内镜像",
        "url": "https://example.invalid/models/embed_min_cn_v1.onnx",
        "checksum": "sha256:abc123"
      }
    ]
  }
]
'''),
    );

    final catalog = await repository.loadCatalog();

    expect(catalog.single.sources.single.checksum, 'sha256:abc123');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`
Expected: FAIL because `ModelSourceEntry` does not expose `checksum` yet.

- [ ] **Step 3: Add checksum field to source metadata and built-in catalog**

```dart
class ModelSourceEntry {
  const ModelSourceEntry({
    required this.id,
    required this.label,
    required this.url,
    required this.checksum,
  });

  factory ModelSourceEntry.fromJson(Map<String, dynamic> json) {
    return ModelSourceEntry(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      url: json['url'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
    );
  }

  final String id;
  final String label;
  final String url;
  final String checksum;
}
```

```json
{
  "id": "official-cn",
  "label": "国内镜像",
  "url": "https://example.invalid/models/embed_min_cn_v1.onnx",
  "checksum": "sha256:replace-with-real-digest"
}
```

- [ ] **Step 4: Run catalog parsing test to verify it passes**

Run: `flutter test test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`
Expected: PASS

### Task 2: Download checksum verification

**Files:**
- Modify: `lib/features/ai_models/infrastructure/model_download_service.dart`
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`

- [ ] **Step 1: Write failing verification-path tests**

```dart
test('startDownload stores checksum when verification succeeds', () async {
  final downloadService = _FakeDownloadService(
    result: const ModelDownloadResult(
      localPath: '/models/embed-1.onnx',
      totalBytes: 4096,
      verifiedChecksum: 'sha256:verified',
    ),
  );

  // ... existing ProviderContainer setup ...

  expect(registryRepository.entries['embed-1']?.checksum, 'sha256:verified');
});

test('startDownload marks task failed when checksum verification fails', () async {
  final downloadService = _FakeDownloadService(
    error: StateError('Checksum mismatch for embed-1'),
  );

  // ... existing ProviderContainer setup ...

  expect(downloadRepository.tasks['embed-1']?.status, ModelDownloadStatus.failed);
  expect(registryRepository.entries.containsKey('embed-1'), isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart`
Expected: FAIL because `ModelDownloadResult` and production code do not carry verified checksum yet.

- [ ] **Step 3: Add checksum verification API to download service**

```dart
class ModelDownloadResult {
  const ModelDownloadResult({
    required this.localPath,
    required this.totalBytes,
    required this.verifiedChecksum,
  });

  final String localPath;
  final int totalBytes;
  final String verifiedChecksum;
}

Future<ModelDownloadResult> download({
  required String taskId,
  required String modelId,
  required String sourceUrl,
  required String expectedChecksum,
  required void Function(ModelDownloadProgress progress) onProgress,
}) async {
  // download file first
  final verifiedChecksum = await verifyChecksum(
    filePath: targetFile.path,
    expectedChecksum: expectedChecksum,
  );
  return ModelDownloadResult(
    localPath: targetFile.path,
    totalBytes: fileLength,
    verifiedChecksum: verifiedChecksum,
  );
}
```

```dart
Future<String> verifyChecksum({
  required String filePath,
  required String expectedChecksum,
}) async {
  final normalized = expectedChecksum.trim().toLowerCase();
  if (!normalized.startsWith('sha256:')) {
    throw StateError('Unsupported checksum format: $expectedChecksum');
  }

  final digest = await _computeSha256(filePath);
  final verified = 'sha256:$digest';
  if (verified != normalized) {
    throw StateError('Checksum mismatch for $filePath');
  }
  return verified;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart`
Expected: PASS

### Task 3: Controller integration and registry persistence

**Files:**
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`

- [ ] **Step 1: Wire expected checksum through the controller**

```dart
final result = await _downloadService.download(
  taskId: task.id,
  modelId: entry.id,
  sourceUrl: source.url,
  expectedChecksum: source.checksum,
  onProgress: (progress) async {
    // existing progress logic
  },
);
```

- [ ] **Step 2: Persist verified checksum only after successful verification**

```dart
await _registryRepository.save(
  ModelRegistryEntry(
    id: entry.id,
    type: entry.type,
    provider: 'builtin_catalog',
    name: entry.displayName,
    version: null,
    sizeBytes: result.totalBytes,
    quantization: null,
    minRamMb: entry.minRamMb,
    recommendedTier: entry.recommendedTier,
    localPath: result.localPath,
    checksum: result.verifiedChecksum,
    enabled: true,
    installedAt: DateTime.now(),
    filePresent: true,
  ),
);
```

- [ ] **Step 3: Keep mismatch path in failed state without registry write**

```dart
} catch (error, stackTrace) {
  _logger.error('Model download failed for ${entry.id}', error, stackTrace);
  await markFailed(entry.id, error.toString());
}
```

This step reuses the existing failure path; do not add any fallback registry write for checksum failures.

- [ ] **Step 4: Run the focused tests**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart`
Expected: PASS

Run: `flutter test test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`
Expected: PASS

### Task 4: Final verification

**Files:**
- Verify: `lib/features/ai_models/domain/model_catalog_entry.dart`
- Verify: `lib/features/ai_models/infrastructure/model_download_service.dart`
- Verify: `lib/features/ai_models/application/model_download_providers.dart`
- Verify: `assets/model_catalog/built_in_catalog.json`
- Verify: `test/features/ai_models/application/model_download_providers_test.dart`
- Verify: `test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`

- [ ] **Step 1: Run all related ai_models tests**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/application/model_selection_providers_test.dart test/features/ai_models/presentation/model_management_page_test.dart test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`
Expected: PASS

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Update the Phase 1 report**

Edit `第一阶段产品进度报告.md` to reflect that model download management now includes checksum verification, while checksum is complete but signature verification, resume, failover, benchmark, and real publishable model resources remain pending.

- [ ] **Step 4: Re-run the focused ai_models tests after the report update**

Run: `flutter test test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`
Expected: PASS
