# Model Presentation Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a shared pure-string presentation helper for model capability summary and deployment-status text, while preserving all current widget output in `SearchSettingsPage` and `ModelManagementPage`.

**Architecture:** Create one narrow helper file under `lib/features/ai_models/presentation/` that contains only pure string-formatting functions. Replace duplicated local formatting logic in the two page files with imports from that helper, then verify the refactor with helper-level tests plus the existing widget test suites.

**Tech Stack:** Flutter, Dart, flutter_test, flutter_riverpod

---

## File Structure

- Create: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
  - Holds pure string-formatting helpers for model summary and deployment status.
- Modify: `lib/features/search/presentation/search_settings_page.dart`
  - Remove local formatting duplication and call the shared helper.
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
  - Remove local formatting duplication and call the shared helper.
- Create: `test/features/ai_models/presentation/model_presentation_formatter_test.dart`
  - Add focused tests for the helper functions.

No widget layout changes, no provider changes, and no new user-visible wording are needed.

### Task 1: Add failing helper tests for summary and deployment formatting

**Files:**
- Create: `test/features/ai_models/presentation/model_presentation_formatter_test.dart`
- Create: `lib/features/ai_models/presentation/model_presentation_formatter.dart`

- [ ] **Step 1: Create the helper test file with imports and a full-metadata summary test**

Create `test/features/ai_models/presentation/model_presentation_formatter_test.dart` with these imports and the first failing test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_presentation_formatter.dart';

void main() {
  test('formatModelCapabilitySummary shows all supported metadata in the approved order', () {
    const model = ModelRegistryEntry(
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
    );

    expect(
      formatModelCapabilitySummary(model),
      'builtin · embedding · Q8 · 版本 1.0.2 · 10.0 MB · RAM ≥ 512MB · 推荐档位 mvp',
    );
  });
}
```

- [ ] **Step 2: Run the helper test to verify it fails**

Run: `flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart --plain-name "formatModelCapabilitySummary shows all supported metadata in the approved order"`

Expected: FAIL because the helper file does not exist yet.

- [ ] **Step 3: Add the remaining failing helper tests**

Extend the same file with these tests:

```dart
test('formatModelCapabilitySummary omits absent metadata', () {
  const model = ModelRegistryEntry(
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
  );

  expect(formatModelCapabilitySummary(model), 'builtin · embedding');
});

test('formatSearchSettingsDeploymentStatus returns ready wording for installed model', () {
  const model = ModelRegistryEntry(
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
  );

  expect(
    formatSearchSettingsDeploymentStatus(model),
    '部署状态：本地文件已就绪，可用于当前语义检索。',
  );
});

test('formatSearchSettingsDeploymentStatus returns degraded wording for missing-file model', () {
  const model = ModelRegistryEntry(
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
  );

  expect(
    formatSearchSettingsDeploymentStatus(model),
    '部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。',
  );
});

test('formatInstalledModelDeploymentStatus returns ready wording for installed model', () {
  const model = ModelRegistryEntry(
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
  );

  expect(formatInstalledModelDeploymentStatus(model), '部署状态：本地文件已就绪。');
});

test('formatInstalledModelDeploymentStatus returns degraded wording for missing-file model', () {
  const model = ModelRegistryEntry(
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
  );

  expect(
    formatInstalledModelDeploymentStatus(model),
    '部署状态：本地文件缺失，当前记录不可直接使用。',
  );
});

test('formatCatalogDeploymentStatus returns not-downloaded wording for null entry', () {
  expect(formatCatalogDeploymentStatus(null), '部署状态：尚未下载到本地。');
});

test('formatCatalogDeploymentStatus returns ready wording for installed entry', () {
  const model = ModelRegistryEntry(
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
  );

  expect(
    formatCatalogDeploymentStatus(model),
    '部署状态：已下载到本地，可立即用于后续启用或检索配置。',
  );
});

test('formatCatalogDeploymentStatus returns degraded wording for missing-file entry', () {
  const model = ModelRegistryEntry(
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
  );

  expect(
    formatCatalogDeploymentStatus(model),
    '部署状态：本地记录存在，但文件缺失，需要重新下载。',
  );
});
```

- [ ] **Step 4: Run the helper test file to verify it still fails for the expected reason**

Run: `flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart --plain-name "format"`

Expected: FAIL because the helper implementation does not exist yet.

- [ ] **Step 5: Implement the minimal helper file**

Create `lib/features/ai_models/presentation/model_presentation_formatter.dart` with this implementation:

```dart
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

String formatModelCapabilitySummary(ModelRegistryEntry model) {
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

String formatSearchSettingsDeploymentStatus(ModelRegistryEntry model) {
  if (model.isInstalled) {
    return '部署状态：本地文件已就绪，可用于当前语义检索。';
  }
  return '部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。';
}

String formatInstalledModelDeploymentStatus(ModelRegistryEntry entry) {
  if (entry.isInstalled) {
    return '部署状态：本地文件已就绪。';
  }
  return '部署状态：本地文件缺失，当前记录不可直接使用。';
}

String formatCatalogDeploymentStatus(ModelRegistryEntry? installedEntry) {
  if (installedEntry == null) {
    return '部署状态：尚未下载到本地。';
  }
  if (installedEntry.isInstalled) {
    return '部署状态：已下载到本地，可立即用于后续启用或检索配置。';
  }
  return '部署状态：本地记录存在，但文件缺失，需要重新下载。';
}

String _formatModelSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) {
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
  return '${mb.toStringAsFixed(1)} MB';
}
```

- [ ] **Step 6: Run the helper test file to verify it passes**

Run: `flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart --plain-name "format"`

Expected: PASS.

### Task 2: Refactor SearchSettingsPage to use the helper without changing output

**Files:**
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Test: `test/features/search/presentation/search_settings_page_test.dart`

- [ ] **Step 1: Update imports and replace local formatter calls**

In `search_settings_page.dart`:

1. Add:

```dart
import 'package:note_secret_search/features/ai_models/presentation/model_presentation_formatter.dart';
```

2. Replace:

```dart
_modelSummary(readiness.activeEmbeddingModel!)
```

with:

```dart
formatModelCapabilitySummary(readiness.activeEmbeddingModel!)
```

3. Replace:

```dart
_deploymentStatus(readiness.activeEmbeddingModel!)
```

with:

```dart
formatSearchSettingsDeploymentStatus(readiness.activeEmbeddingModel!)
```

4. Delete the local methods:

```dart
String _modelSummary(...)
String _formatModelSize(...)
String _deploymentStatus(...)
```

- [ ] **Step 2: Run SearchSettingsPage widget tests to verify behavior is unchanged**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage"`

Expected: PASS.

### Task 3: Refactor ModelManagementPage to use the helper without changing output

**Files:**
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Test: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Replace local formatting functions with helper imports**

In `model_management_page.dart`:

1. Add:

```dart
import 'package:note_secret_search/features/ai_models/presentation/model_presentation_formatter.dart';
```

2. Replace:

```dart
_modelSummary(entry)
```

with:

```dart
formatModelCapabilitySummary(entry)
```

3. Replace:

```dart
_installedModelDeploymentStatus(entry)
```

with:

```dart
formatInstalledModelDeploymentStatus(entry)
```

4. Replace:

```dart
_catalogDeploymentStatus()
```

with:

```dart
formatCatalogDeploymentStatus(installedEntry)
```

5. Delete the local top-level functions:

```dart
String _modelSummary(...)
String _formatModelSize(...)
String _installedModelDeploymentStatus(...)
```

6. Delete the `_catalogDeploymentStatus()` method from `_CatalogEntryTile`.

- [ ] **Step 2: Run ModelManagementPage widget tests to verify behavior is unchanged**

Run: `flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage"`

Expected: PASS.

### Task 4: Run full verification for the refactor slice

**Files:**
- Create: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Create: `test/features/ai_models/presentation/model_presentation_formatter_test.dart`

- [ ] **Step 1: Run the helper tests**

Run: `flutter test test/features/ai_models/presentation/model_presentation_formatter_test.dart`

Expected: PASS.

- [ ] **Step 2: Run both widget test groups**

Run: `flutter test test/features/search/presentation/search_settings_page_test.dart --plain-name "SearchSettingsPage" && flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage"`

Expected: PASS.

- [ ] **Step 3: Run Flutter analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Run diagnostics on all changed files**

Check diagnostics for:

- `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- `lib/features/search/presentation/search_settings_page.dart`
- `lib/features/ai_models/presentation/model_management_page.dart`
- `test/features/ai_models/presentation/model_presentation_formatter_test.dart`

Expected: no errors.

- [ ] **Step 5: Review behavior-preserving scope before claiming completion**

Confirm that:

- wording did not change
- summary field ordering did not change
- deployment-status branching did not change
- widget structure remained effectively the same
- only formatting logic location changed

- [ ] **Step 6: Do not commit unless explicitly requested**

Leave the work uncommitted unless the user separately asks for a git commit.

---

## Self-Review

### Spec coverage

- Shared helper extraction: covered by Task 1.
- SearchSettingsPage migration: covered by Task 2.
- ModelManagementPage migration: covered by Task 3.
- Behavior-preserving verification: covered by Task 4.

### Placeholder scan

No `TODO`, `TBD`, or vague implementation instructions remain.

### Type consistency

- Helper signatures match the approved spec and current types.
- `ModelRegistryEntry` remains the only input type needed for summary and installed/search-settings deployment helpers.
- `ModelRegistryEntry?` remains the only input needed for catalog deployment status.
