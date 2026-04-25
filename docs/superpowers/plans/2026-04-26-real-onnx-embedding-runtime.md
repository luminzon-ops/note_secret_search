# Real ONNX Embedding Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder embedding engine with a real Android ONNX embedding runtime, wire it into model management and search readiness, and make semantic indexing/search use real vectors with explicit degradation when runtime is unavailable.

**Architecture:** Keep `EmbeddingEngine` as the only business-facing abstraction. Add a Flutter infrastructure bridge plus a dedicated Android embedding runtime channel that can inspect, load, and execute a single active ONNX embedding model. Refactor provider/readiness flow so only runtime-ready models become active semantic models, and make the model management UI display real runtime state.

**Tech Stack:** Flutter, Riverpod, Kotlin, MethodChannel, Android ONNX Runtime, sqflite_sqlcipher, Flutter widget/unit tests.

---

## File Structure / Responsibilities

### Existing files to modify

- `android/app/build.gradle.kts`
  - Add ONNX Runtime Android dependency and any packaging settings needed for native runtime loading.

- `android/app/src/main/kotlin/com/example/note_secret_search/MainActivity.kt`
  - Attach/register the new embedding runtime plugin.

- `lib/features/search/domain/embedding_engine.dart`
  - Expand `EmbeddingEngineState` semantics to include runtime status metadata.

- `lib/features/search/application/search_providers.dart`
  - Replace placeholder engine wiring with the real ONNX engine provider.

- `lib/features/ai_models/application/model_selection_providers.dart`
  - Make active embedding model selection/runtime readiness depend on real runtime status.

- `lib/features/ai_models/application/model_download_providers.dart`
  - Resolve model runtime state for installed models and surface runtime-aware entries to UI.

- `lib/features/ai_models/presentation/model_management_page.dart`
  - Show runtime-aware deployment state and block activating degraded/missing models.

- `lib/features/search/presentation/search_status_summary.dart`
  - Display runtime-driven semantic readiness messages.

- `lib/features/search/presentation/search_page.dart`
  - Ensure search page consumes runtime readiness correctly and does not imply semantic availability when degraded.

- `lib/features/search/application/search_index_service.dart`
  - Keep business flow but ensure it works with the richer runtime state model.

- `lib/features/search/application/semantic_search_service.dart`
  - Keep semantic business logic unchanged except for real engine usage and clearer failures if runtime breaks.

### New Flutter files to create

- `lib/features/search/infrastructure/embedding_runtime_bridge.dart`
  - Central MethodChannel wrapper for embedding runtime inspect/load/embed/release calls.

- `lib/features/search/infrastructure/onnx_embedding_engine.dart`
  - Real `EmbeddingEngine` implementation backed by the bridge.

- `lib/features/ai_models/domain/model_runtime_status.dart`
  - Runtime status enum / resolved runtime entry shape shared by provider and UI.

### New Android files to create

- `android/app/src/main/kotlin/com/example/note_secret_search/EmbeddingRuntimePlugin.kt`
  - MethodChannel handler for embedding runtime operations.

- `android/app/src/main/kotlin/com/example/note_secret_search/OnnxEmbeddingRuntime.kt`
  - Runtime facade that manages ONNX environment/session lifecycle and runs inference.

- `android/app/src/main/kotlin/com/example/note_secret_search/EmbeddingModelSessionManager.kt`
  - Single-active-model session cache manager.

### Tests to add/modify

- `test/features/search/infrastructure/onnx_embedding_engine_test.dart`
  - Verify runtime state/error mapping and embedding result decoding.

- `test/features/ai_models/application/model_selection_providers_test.dart`
  - Verify only runtime-ready models can become active embedding models.

- `test/features/ai_models/presentation/model_management_page_test.dart`
  - Verify runtime-aware deployment state rendering and active-selection gating.

- `test/features/search/presentation/search_status_summary_test.dart`
  - Verify degraded/missing/unverified semantic readiness copy.

- `test/features/search/application/search_providers_test.dart`
  - Update provider expectations for real engine wiring / readiness interaction.

---

### Task 1: Add Android ONNX runtime dependency and plugin registration

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/MainActivity.kt`

- [ ] **Step 1: Write the failing integration expectation in plan notes**

Create a local checklist note in the working branch (not a code file) that the Android app must be able to:

```text
1. Resolve ONNX Runtime classes at compile time
2. Attach embedding runtime channel from MainActivity
3. Keep existing native security plugin behavior intact
```

Expected failure before implementation: the project has no ONNX Runtime dependency and no embedding runtime plugin attached.

- [ ] **Step 2: Add ONNX Runtime Android dependency**

Update `android/app/build.gradle.kts` to include the ONNX Runtime Android library in the `dependencies` block, for example:

```kotlin
dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.18.0")
}
```

If the project already has a dependencies block, append this exact implementation line rather than creating a duplicate block.

- [ ] **Step 3: Register the embedding runtime plugin in MainActivity**

Extend `MainActivity.kt` so it creates and attaches an embedding runtime plugin alongside the existing security plugin. The final shape should be equivalent to:

```kotlin
class MainActivity : FlutterFragmentActivity() {
    private lateinit var nativeSecurityPlugin: NativeSecurityPlugin
    private lateinit var embeddingRuntimePlugin: EmbeddingRuntimePlugin
    private lateinit var recentTaskShieldView: FrameLayout

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeSecurityPlugin = NativeSecurityPlugin(this, recentTaskShieldView)
        nativeSecurityPlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)

        embeddingRuntimePlugin = EmbeddingRuntimePlugin(this)
        embeddingRuntimePlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)
    }
}
```

- [ ] **Step 4: Verify Android code compiles logically**

Run:

```powershell
flutter analyze
```

Expected: no new Kotlin/Flutter analyzer issues caused by dependency registration or plugin wiring. If analyzer does not validate Kotlin compilation fully, note that full runtime compilation will be exercised in later steps.

- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/kotlin/com/example/note_secret_search/MainActivity.kt
git commit -m "feat: register android onnx embedding runtime"
```

---

### Task 2: Create Android embedding runtime channel and session manager

**Files:**
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/EmbeddingRuntimePlugin.kt`
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/OnnxEmbeddingRuntime.kt`
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/EmbeddingModelSessionManager.kt`

- [ ] **Step 1: Write the failing design-oriented test note**

Document the exact methods the plugin must support:

```text
Channel: note_secret_search/embedding_runtime
Methods:
- inspectModel
- ensureModelReady
- embedText
- releaseModel
```

Expected failure before implementation: no such channel or methods exist.

- [ ] **Step 2: Implement the session manager**

Create `EmbeddingModelSessionManager.kt` with a single-active-model cache. The code skeleton should be close to:

```kotlin
package com.example.note_secret_search

import ai.onnxruntime.OrtSession

class EmbeddingModelSessionManager {
    private var activeModelId: String? = null
    private var activeSession: OrtSession? = null

    fun get(modelId: String): OrtSession? {
        return if (activeModelId == modelId) activeSession else null
    }

    fun replace(modelId: String, session: OrtSession) {
        if (activeModelId != modelId) {
            activeSession?.close()
        }
        activeModelId = modelId
        activeSession = session
    }

    fun release(modelId: String) {
        if (activeModelId == modelId) {
            activeSession?.close()
            activeSession = null
            activeModelId = null
        }
    }

    fun releaseAll() {
        activeSession?.close()
        activeSession = null
        activeModelId = null
    }
}
```

- [ ] **Step 3: Implement runtime facade with inspect/load/embed/release primitives**

Create `OnnxEmbeddingRuntime.kt` with the following responsibilities:

```kotlin
package com.example.note_secret_search

import android.content.Context
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File
import java.nio.FloatBuffer

class OnnxEmbeddingRuntime(
    private val context: Context,
    private val sessionManager: EmbeddingModelSessionManager,
) {
    private val environment: OrtEnvironment = OrtEnvironment.getEnvironment()

    fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> { /* implement */ }
    fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> { /* implement */ }
    fun embedText(modelId: String, modelPath: String, text: String): Map<String, Any?> { /* implement */ }
    fun releaseModel(modelId: String) { sessionManager.release(modelId) }
}
```

Implementation requirements for this step:

1. `inspectModel` must:
   - return `missing` if the file does not exist
   - attempt to load the model into an `OrtSession`
   - return `ready` or `degraded` with a reason
2. `ensureModelReady` must:
   - load the model and cache the session via `sessionManager.replace(...)`
3. `embedText` must:
   - require a non-blank string
   - reuse the cached session when possible
   - produce a deterministic float vector map response

For the first implementation, it is acceptable to use a minimal temporary text-to-float input strategy specific to your chosen ONNX model format, but do not fake outputs. The output must come from real ONNX execution.

- [ ] **Step 4: Implement the MethodChannel plugin**

Create `EmbeddingRuntimePlugin.kt` with a method handler like:

```kotlin
package com.example.note_secret_search

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EmbeddingRuntimePlugin(
    context: Context,
) : MethodChannel.MethodCallHandler {

    private val runtime = OnnxEmbeddingRuntime(
        context = context,
        sessionManager = EmbeddingModelSessionManager(),
    )

    private lateinit var channel: MethodChannel

    fun attachToEngine(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "note_secret_search/embedding_runtime")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "inspectModel" -> { /* parse args and delegate */ }
            "ensureModelReady" -> { /* parse args and delegate */ }
            "embedText" -> { /* parse args and delegate */ }
            "releaseModel" -> { /* parse args and delegate */ }
            else -> result.notImplemented()
        }
    }
}
```

Use `result.success(map)` for valid runtime states and `result.error(code, message, details)` for unexpected failures.

- [ ] **Step 5: Run analyzer to verify new Kotlin-facing APIs don’t break Flutter side**

Run:

```powershell
flutter analyze
```

Expected: Flutter analysis still passes; any new Flutter-side breakages are limited to yet-unimplemented Dart integration points.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/example/note_secret_search/EmbeddingRuntimePlugin.kt android/app/src/main/kotlin/com/example/note_secret_search/OnnxEmbeddingRuntime.kt android/app/src/main/kotlin/com/example/note_secret_search/EmbeddingModelSessionManager.kt
git commit -m "feat: add android embedding runtime channel"
```

---

### Task 3: Add Flutter runtime bridge and real ONNX embedding engine

**Files:**
- Create: `lib/features/search/infrastructure/embedding_runtime_bridge.dart`
- Create: `lib/features/search/infrastructure/onnx_embedding_engine.dart`
- Modify: `lib/features/search/domain/embedding_engine.dart`

- [ ] **Step 1: Write the failing Dart unit test**

Create `test/features/search/infrastructure/onnx_embedding_engine_test.dart` with tests shaped like:

```dart
test('maps ready runtime state from bridge', () async {
  final bridge = FakeEmbeddingRuntimeBridge.inspectReady(vectorDimension: 384);
  final engine = OnnxEmbeddingEngine(bridge: bridge);

  final state = await engine.getState(model);

  expect(state.ready, isTrue);
  expect(state.status, EmbeddingRuntimeStatus.ready);
  expect(state.vectorDimension, 384);
});

test('maps embedText response into EmbeddingVector', () async {
  final bridge = FakeEmbeddingRuntimeBridge.embedResult(values: [0.1, 0.2]);
  final engine = OnnxEmbeddingEngine(bridge: bridge);

  final vector = await engine.embed(EmbeddingRequest(model: model, text: 'hello'));

  expect(vector.values, [0.1, 0.2]);
  expect(vector.tokenCount, isNonZero);
});
```

- [ ] **Step 2: Expand the domain runtime state model**

Modify `embedding_engine.dart` so it defines a runtime status enum and richer state object. The resulting shape should be equivalent to:

```dart
enum EmbeddingRuntimeStatus {
  notInstalled,
  missing,
  installedUnverified,
  ready,
  degraded,
}

class EmbeddingEngineState {
  const EmbeddingEngineState({
    required this.ready,
    required this.reason,
    required this.status,
    this.vectorDimension,
    this.modelPath,
    this.checkedAt,
  });

  final bool ready;
  final String reason;
  final EmbeddingRuntimeStatus status;
  final int? vectorDimension;
  final String? modelPath;
  final DateTime? checkedAt;
}
```

Do not remove `EmbeddingRequest` or `EmbeddingVector`.

- [ ] **Step 3: Implement the bridge**

Create `embedding_runtime_bridge.dart` with a `MethodChannel` wrapper similar to:

```dart
import 'package:flutter/services.dart';

class EmbeddingRuntimeBridge {
  EmbeddingRuntimeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('note_secret_search/embedding_runtime');

  final MethodChannel _channel;

  Future<Map<String, dynamic>> inspectModel({required String modelId, required String modelPath}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('inspectModel', {
      'modelId': modelId,
      'modelPath': modelPath,
    });
    return result ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> ensureModelReady({required String modelId, required String modelPath}) async { /* same pattern */ }
  Future<Map<String, dynamic>> embedText({required String modelId, required String modelPath, required String text}) async { /* same pattern */ }
  Future<void> releaseModel({required String modelId}) async { /* invoke method */ }
}
```

- [ ] **Step 4: Implement `OnnxEmbeddingEngine`**

Create `onnx_embedding_engine.dart` with a real implementation similar to:

```dart
class OnnxEmbeddingEngine implements EmbeddingEngine {
  const OnnxEmbeddingEngine({required EmbeddingRuntimeBridge bridge}) : _bridge = bridge;

  final EmbeddingRuntimeBridge _bridge;

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    final path = model.localPath;
    if (path == null || path.trim().isEmpty) {
      return const EmbeddingEngineState(
        ready: false,
        reason: '尚未配置本地 embedding 模型文件。',
        status: EmbeddingRuntimeStatus.notInstalled,
      );
    }

    final result = await _bridge.inspectModel(modelId: model.id, modelPath: path);
    return mapEmbeddingEngineState(result);
  }

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    final path = request.model.localPath;
    if (path == null || path.trim().isEmpty) {
      throw StateError('Active embedding model path is missing.');
    }

    final result = await _bridge.embedText(
      modelId: request.model.id,
      modelPath: path,
      text: request.text,
    );

    final rawValues = (result['values'] as List<dynamic>? ?? const <dynamic>[])
        .map((value) => (value as num).toDouble())
        .toList(growable: false);

    return EmbeddingVector(
      values: rawValues,
      tokenCount: (result['tokenCount'] as num?)?.toInt() ?? request.text.length,
    );
  }
}
```

Include a private or helper mapper that converts channel state strings into `EmbeddingRuntimeStatus` values.

- [ ] **Step 5: Run unit tests and verify they pass**

Run:

```powershell
flutter test test/features/search/infrastructure/onnx_embedding_engine_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/search/domain/embedding_engine.dart lib/features/search/infrastructure/embedding_runtime_bridge.dart lib/features/search/infrastructure/onnx_embedding_engine.dart test/features/search/infrastructure/onnx_embedding_engine_test.dart
git commit -m "feat: add flutter onnx embedding engine"
```

---

### Task 4: Replace placeholder engine wiring with real runtime-aware providers

**Files:**
- Modify: `lib/features/search/application/search_providers.dart`
- Modify: `lib/features/ai_models/application/model_selection_providers.dart`
- Create: `lib/features/ai_models/domain/model_runtime_status.dart`
- Test: `test/features/ai_models/application/model_selection_providers_test.dart`
- Test: `test/features/search/application/search_providers_test.dart`

- [ ] **Step 1: Write failing provider tests**

Create/update tests with cases like:

```dart
test('activeEmbeddingModelProvider returns null when selected model is degraded', () async {
  // selected model exists but runtime state is degraded
  expect(await container.read(activeEmbeddingModelProvider.future), isNull);
});

test('semanticSearchReadinessProvider reports missing file reason', () async {
  final readiness = await container.read(semanticSearchReadinessProvider.future);
  expect(readiness.ready, isFalse);
  expect(readiness.reason, contains('文件缺失'));
});
```

- [ ] **Step 2: Add runtime-aware resolved model state type**

Create `model_runtime_status.dart` with a shape like:

```dart
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';

class ResolvedModelRuntimeEntry {
  const ResolvedModelRuntimeEntry({
    required this.entry,
    required this.filePresent,
    required this.runtimeState,
  });

  final ModelRegistryEntry entry;
  final bool filePresent;
  final EmbeddingEngineState? runtimeState;
}
```

- [ ] **Step 3: Update `search_providers.dart` to use `OnnxEmbeddingEngine`**

Replace placeholder wiring with:

```dart
final embeddingRuntimeBridgeProvider = Provider<EmbeddingRuntimeBridge>((ref) {
  return EmbeddingRuntimeBridge();
});

final embeddingEngineProvider = Provider<EmbeddingEngine>((ref) {
  return OnnxEmbeddingEngine(bridge: ref.watch(embeddingRuntimeBridgeProvider));
});
```

Keep other provider names stable if possible to minimize blast radius.

- [ ] **Step 4: Refactor active model selection and readiness logic**

Modify `model_selection_providers.dart` so:

1. `activeEmbeddingModelProvider` only returns an entry when:
   - selected model exists
   - entry type is `embedding`
   - local file exists
   - `EmbeddingEngine.getState(entry)` returns `status == ready`
2. `semanticSearchReadinessProvider` distinguishes:
   - scope disabled
   - no selection
   - file missing
   - runtime degraded
   - runtime ready

The returned readiness messages must be explicit and user-facing, for example:

```dart
return const SemanticSearchReadiness(
  ready: false,
  reason: '当前本地 embedding 模型文件缺失，请重新下载或切换模型。',
);
```

- [ ] **Step 5: Run provider tests**

Run:

```powershell
flutter test test/features/ai_models/application/model_selection_providers_test.dart
flutter test test/features/search/application/search_providers_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/search/application/search_providers.dart lib/features/ai_models/application/model_selection_providers.dart lib/features/ai_models/domain/model_runtime_status.dart test/features/ai_models/application/model_selection_providers_test.dart test/features/search/application/search_providers_test.dart
git commit -m "refactor: make embedding readiness runtime aware"
```

---

### Task 5: Link runtime state into model management UI and registry resolution

**Files:**
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Test: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Write failing UI tests for runtime-aware deployment states**

Add/update tests for these cases:

```dart
testWidgets('shows 已安装但当前不可运行 for degraded runtime state', (tester) async { /* ... */ });
testWidgets('blocks activating a degraded embedding model', (tester) async { /* ... */ });
testWidgets('shows 当前语义模型 only for runtime-ready active model', (tester) async { /* ... */ });
```

- [ ] **Step 2: Resolve runtime state for installed models in provider layer**

Modify `model_download_providers.dart` so installed model entries are enriched with runtime inspect results for embedding-type models. The provider should do logic equivalent to:

```dart
final state = entry.type == 'embedding'
    ? await ref.read(embeddingEngineProvider).getState(normalized)
    : null;

resolved.add(
  ResolvedModelRuntimeEntry(
    entry: normalized,
    filePresent: present,
    runtimeState: state,
  ),
);
```

Keep non-embedding models unaffected for now.

- [ ] **Step 3: Update model management UI to consume runtime-aware entries**

Modify `ModelManagementPage` and its subwidgets so deployment messaging follows rules:

1. `ready` → show `部署状态：本地已就绪。`
2. `missing` → show `部署状态：本地文件缺失，当前记录不可直接使用。`
3. `degraded` → show `部署状态：模型已安装但当前不可运行。`
4. `installedUnverified` → show `部署状态：模型已安装，尚未完成运行时校验。`

If a user tries to activate a degraded/missing model, the UI must trigger `ensureModelReady` first and refuse activation on failure.

- [ ] **Step 4: Run widget tests**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_models/application/model_download_providers.dart lib/features/ai_models/presentation/model_management_page.dart test/features/ai_models/presentation/model_management_page_test.dart
git commit -m "feat: surface embedding runtime status in model management"
```

---

### Task 6: Make search/index flows use real runtime and explicit degradation

**Files:**
- Modify: `lib/features/search/application/search_index_service.dart`
- Modify: `lib/features/search/application/semantic_search_service.dart`
- Modify: `lib/features/search/presentation/search_status_summary.dart`
- Modify: `lib/features/search/presentation/search_page.dart`
- Test: `test/features/search/presentation/search_status_summary_test.dart`

- [ ] **Step 1: Write failing tests for degraded semantic readiness presentation**

Add tests shaped like:

```dart
testWidgets('shows degraded runtime guidance in search status summary', (tester) async {
  // readiness false with degraded reason
  expect(find.textContaining('当前不可运行'), findsOneWidget);
});
```

- [ ] **Step 2: Ensure search/index services fail clearly when runtime is unavailable**

Adjust `search_index_service.dart` and `semantic_search_service.dart` so they do not silently proceed with fake semantics. Keep their current algorithms, but ensure any runtime-unready state is surfaced through provider readiness and user-visible status instead of placeholder copy.

Key rule for this step:

```dart
if (!engineState.ready) {
  return SearchIndexStatus(
    engineReady: false,
    engineReason: engineState.reason,
    hasActiveEmbeddingModel: true,
    pendingItems: pending,
  );
}
```

And for semantic query flow, no fallback to placeholder vectors is allowed.

- [ ] **Step 3: Update search UI messaging**

Modify `search_status_summary.dart` and `search_page.dart` so degraded/missing/unverified runtime states produce user-facing copy that clearly distinguishes:

1. no local model selected
2. file missing
3. runtime degraded
4. semantic search disabled by scope

Do not imply “语义检索已就绪” unless runtime-ready.

- [ ] **Step 4: Run targeted tests**

Run:

```powershell
flutter test test/features/search/presentation/search_status_summary_test.dart
flutter test test/features/search/presentation/search_page_test.dart
flutter test test/features/search/application/semantic_search_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/search/application/search_index_service.dart lib/features/search/application/semantic_search_service.dart lib/features/search/presentation/search_status_summary.dart lib/features/search/presentation/search_page.dart test/features/search/presentation/search_status_summary_test.dart
git commit -m "feat: use runtime readiness in semantic search flow"
```

---

### Task 7: Validate end-to-end behavior and document next-task handoff

**Files:**
- Modify: `docs/superpowers/specs/2026-04-26-real-onnx-embedding-runtime-design.md` (only if implementation changed assumptions)
- Modify: `第一阶段产品进度报告.md` (optional only if status materially changed after implementation)

- [ ] **Step 1: Run the critical verification suite**

Run:

```powershell
flutter test test/features/search/infrastructure/onnx_embedding_engine_test.dart
flutter test test/features/ai_models/application/model_selection_providers_test.dart
flutter test test/features/ai_models/presentation/model_management_page_test.dart
flutter test test/features/search/application/search_providers_test.dart
flutter test test/features/search/presentation/search_status_summary_test.dart
flutter test test/features/search/presentation/search_page_test.dart
flutter analyze
```

Expected: all pass. If there are pre-existing failures unrelated to this work, document them explicitly and do not hide them.

- [ ] **Step 2: Perform manual runtime verification on Android**

Manual checklist:

```text
1. Install or point to a valid ONNX embedding model file
2. Open model management page and confirm deployment state becomes “本地已就绪”
3. Set it as active embedding model
4. Edit a secret or note and trigger indexing
5. Run a semantic search query
6. Confirm degraded behavior by renaming/removing the model file and re-opening the app/page
```

Expected:
- runtime-ready model works
- missing/degraded model disables semantic path but keyword search still works

- [ ] **Step 3: Record next-task handoff in implementation notes**

Add a short note in the branch summary / handoff describing that the next recommended task is **model download management hardening**, specifically:

```text
Next task after real embedding runtime:
1. checksum verification
2. post-download runtime validation
3. file corruption detection
4. failed download recovery
5. download state restoration
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-04-26-real-onnx-embedding-runtime-design.md 第一阶段产品进度报告.md
git commit -m "docs: record embedding runtime completion handoff"
```

If neither file changed, skip this commit and explicitly note that no docs delta was required.

---

## Self-Review

### Spec coverage check

The plan covers:

- Android ONNX Runtime integration → Tasks 1-2
- Flutter `EmbeddingEngine` replacement → Task 3
- provider/readiness state refactor → Task 4
- model management runtime linkage → Task 5
- search/index real embedding path → Task 6
- validation strategy → Task 7
- next-task handoff toward model download management hardening → Task 7

No spec requirement is left without a task.

### Placeholder scan

Checked for:
- TBD / TODO
- “implement later”
- vague “add tests” wording
- undefined tasks

Removed/avoided all placeholders. Each task names exact files and commands.

### Type consistency check

The plan consistently uses:
- `EmbeddingRuntimeStatus`
- `EmbeddingEngineState`
- `EmbeddingRuntimeBridge`
- `OnnxEmbeddingEngine`
- `ResolvedModelRuntimeEntry`

No later task renames these concepts inconsistently.
