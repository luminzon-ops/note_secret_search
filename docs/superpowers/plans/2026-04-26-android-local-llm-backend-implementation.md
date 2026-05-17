# Android Local LLM Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current Android `LocalLlmRuntime` stub with a real local inference backend adapter while keeping the existing Flutter model-management, AI chat, and session-persistence flows stable.

**Architecture:** Keep the Flutter `LlmRuntimeBridge` / `LocalLlmEngine` / provider API stable. Refactor Android into a runtime facade (`LocalLlmRuntime`) plus a backend abstraction/factory and a first real backend implementation, then propagate truthful runtime states through existing Flutter providers and chat orchestration. Follow the existing embedding runtime conventions where they still fit, but make LLM readiness stricter by requiring a real generation probe before returning `ready`.

**Tech Stack:** Flutter, Riverpod, Kotlin, MethodChannel, Android local file/runtime integration, existing ONNX-style runtime conventions, focused Flutter tests, Flutter analyze.

---

## File Structure / Responsibilities

### Existing files to modify

- `android/app/build.gradle.kts`
  - Add the Android-side dependency for the first real GGUF backend: `io.github.ljcamargo:llamacpp-kotlin:0.2.0`.

- `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`
  - Convert from stub to orchestration facade that selects a backend, manages sessions, runs readiness probes, executes generation, and maps errors/states.

- `android/app/src/main/kotlin/com/example/note_secret_search/LlmModelSessionManager.kt`
  - Continue supporting the single-active-model policy, but adapt generic session handling to the new backend session type and safe release behavior.

- `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt`
  - Keep the MethodChannel contract stable while ensuring the plugin routes to the new real runtime behavior and preserves consistent error mapping.

- `lib/features/ai_chat/infrastructure/local_llm_engine.dart`
  - Extend runtime-state mapping tests/logic for stricter degraded and unsupported-backend states if Android returns new status metadata.

- `lib/features/ai_chat/application/llm_runtime_providers.dart`
  - Preserve provider surface while validating that active-model selection and readiness use the truthful runtime states from the real backend.

- `lib/features/ai_models/application/model_download_providers.dart`
  - Keep post-download runtime verification behavior aligned with the stricter LLM readiness probe.

- `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`
  - Add runtime mapping cases for unsupported/probe-failed/generation-failed state payloads.

- `test/features/ai_chat/application/llm_runtime_providers_test.dart`
  - Add readiness/self-healing cases for stricter truthful runtime states.

- `test/features/ai_chat/application/ai_chat_providers_test.dart`
  - Add orchestration persistence behavior assertions for real runtime error propagation.

### New Android files to create

- `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmBackend.kt`
  - Backend abstraction for inspect/load/generate/release operations.

- `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmBackendSession.kt`
  - Session wrapper/value object for the single active local LLM backend session.

- `android/app/src/main/kotlin/com/example/note_secret_search/LlmBackendFactory.kt`
  - Selects the concrete backend based on model path/format and environment.

- `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt`
  - First real backend implementation for GGUF local generation using `io.github.ljcamargo:llamacpp-kotlin:0.2.0` and its `LlamaHelper` API.

### Existing files to validate but not heavily restructure

- `lib/features/ai_chat/application/ai_chat_providers.dart`
  - Ensure existing assistant error persistence still works with truthful runtime failures.

- `lib/features/ai_models/presentation/model_management_page.dart`
  - Validate UI copy remains correct under the new runtime states.

- `test/features/ai_models/application/model_download_providers_test.dart`
  - Keep the LLM download verification path passing with the stricter backend probe behavior.

- `test/features/ai_models/application/model_selection_providers_test.dart`
  - Keep active LLM self-healing behavior passing with truthful readiness.

---

## Task 1: Add failing runtime mapping and provider tests for truthful backend states

**Files:**
- Modify: `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`
- Modify: `test/features/ai_chat/application/llm_runtime_providers_test.dart`

- [ ] **Step 1: Add a failing runtime mapping test for unsupported backend state**

Add this test to `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`:

```dart
test('maps installed_unverified runtime payload into non-ready state', () {
  const payload = <String, dynamic>{
    'ready': false,
    'reason': '检测到模型文件，但当前 backend 尚未完成真实校验。',
    'status': 'installed_unverified',
    'modelPath': '/data/user/0/app/files/models/phi.gguf',
    'checkedAt': 1714100000000,
  };

  final result = mapLlmRuntimeState(payload);

  expect(result.ready, isFalse);
  expect(result.status, LlmRuntimeStatus.installedUnverified);
  expect(result.reason, '检测到模型文件，但当前 backend 尚未完成真实校验。');
  expect(result.modelPath, '/data/user/0/app/files/models/phi.gguf');
  expect(result.checkedAt, DateTime.fromMillisecondsSinceEpoch(1714100000000));
});
```

- [ ] **Step 2: Add a failing runtime mapping test for probe-failed degraded state**

Add this test to the same file:

```dart
test('maps probe-failed degraded payload into non-ready state', () {
  const payload = <String, dynamic>{
    'ready': false,
    'reason': '本地 LLM readiness probe 失败：backend returned empty text.',
    'status': 'degraded',
    'modelPath': '/data/user/0/app/files/models/phi.gguf',
    'checkedAt': 1714200000000,
  };

  final result = mapLlmRuntimeState(payload);

  expect(result.ready, isFalse);
  expect(result.status, LlmRuntimeStatus.degraded);
  expect(result.reason, contains('probe 失败'));
  expect(result.checkedAt, DateTime.fromMillisecondsSinceEpoch(1714200000000));
});
```

- [ ] **Step 3: Add a failing provider test for self-healing degraded active LLM selection**

Add this test to `test/features/ai_chat/application/llm_runtime_providers_test.dart`:

```dart
test('activeLocalLlmModelProvider removes degraded selected llm model from preferences', () async {
  SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
      modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
      llmRuntimeStatesProvider.overrideWith(
        (ref) async => {
          'llm-1': const LlmRuntimeState(
            ready: false,
            reason: 'probe failed',
            status: LlmRuntimeStatus.degraded,
          ),
        },
      ),
    ],
  );

  addTearDown(container.dispose);

  final model = await container.read(activeLocalLlmModelProvider.future);
  final preferences = await container.read(sharedPreferencesProvider.future);

  expect(model, isNull);
  expect(preferences.getString('ai.active_llm_model_id'), isNull);
});
```

- [ ] **Step 4: Run targeted tests to verify the new cases fail for the right reasons**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart
```

Expected:

- The new tests compile and currently fail only where the implementation has not yet been updated.
- Existing tests should still pass.

- [ ] **Step 5: Commit**

```bash
git add test/features/ai_chat/infrastructure/local_llm_engine_test.dart test/features/ai_chat/application/llm_runtime_providers_test.dart
git commit -m "test: add truthful llm runtime state coverage"
```

---

## Task 2: Introduce Android backend abstraction and session wrapper

**Files:**
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmBackend.kt`
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmBackendSession.kt`
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LlmModelSessionManager.kt`

- [ ] **Step 1: Create the backend abstraction file**

Create `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmBackend.kt` with this content:

```kotlin
package com.example.note_secret_search

import java.io.File

data class LocalLlmInspectResult(
    val supported: Boolean,
    val reason: String,
)

data class LocalLlmGenerateResult(
    val text: String,
    val finishReason: String,
)

interface LocalLlmBackend {
    fun inspect(file: File): LocalLlmInspectResult
    fun load(modelId: String, file: File): LocalLlmBackendSession
    fun generate(
        session: LocalLlmBackendSession,
        prompt: String,
        maxTokens: Int,
    ): LocalLlmGenerateResult
    fun release(session: LocalLlmBackendSession)
}
```

- [ ] **Step 2: Create the backend session wrapper file**

Create `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmBackendSession.kt` with this content:

```kotlin
package com.example.note_secret_search

data class LocalLlmBackendSession(
    val modelId: String,
    val modelPath: String,
    val backendName: String,
    val handle: Any,
)
```

- [ ] **Step 3: Update the session manager to use releaseAll consistently for backend sessions**

Update `android/app/src/main/kotlin/com/example/note_secret_search/LlmModelSessionManager.kt` so the class remains generic but keeps the current single-active-model behavior exactly. No new semantics should be added beyond the existing API. The file should remain:

```kotlin
package com.example.note_secret_search

class LlmModelSessionManager<T> {
    private var activeModelId: String? = null
    private var activeSession: T? = null

    fun get(modelId: String): T? {
        return if (activeModelId == modelId) activeSession else null
    }

    fun replace(modelId: String, session: T, onDispose: (T) -> Unit) {
        if (activeModelId != modelId) {
            activeSession?.let(onDispose)
        }
        activeModelId = modelId
        activeSession = session
    }

    fun release(modelId: String, onDispose: (T) -> Unit) {
        if (activeModelId == modelId) {
            activeSession?.let(onDispose)
            activeModelId = null
            activeSession = null
        }
    }

    fun releaseAll(onDispose: (T) -> Unit) {
        activeSession?.let(onDispose)
        activeModelId = null
        activeSession = null
    }
}
```

- [ ] **Step 4: Run a lightweight Kotlin compile check through Flutter analyze**

Run:

```powershell
flutter analyze
```

Expected:

- Dart analysis still passes.
- No new Android/Kotlin file path issues are introduced.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmBackend.kt android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmBackendSession.kt android/app/src/main/kotlin/com/example/note_secret_search/LlmModelSessionManager.kt
git commit -m "feat: add android llm backend abstractions"
```

---

## Task 3: Add backend factory and a first real GGUF backend implementation

**Files:**
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/LlmBackendFactory.kt`
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt`
- Modify: `android/app/build.gradle.kts`

- [ ] **Step 1: Add the Android dependency for the first real GGUF backend**

Modify `android/app/build.gradle.kts` by adding the first real local LLM backend dependency below the ONNX dependency using this exact line:

```kotlin
implementation("io.github.ljcamargo:llamacpp-kotlin:0.2.0")
```

- [ ] **Step 2: Create the backend factory**

Create `android/app/src/main/kotlin/com/example/note_secret_search/LlmBackendFactory.kt` with this content:

```kotlin
package com.example.note_secret_search

import android.content.Context
import java.io.File

class LlmBackendFactory(
    private val context: Context,
) {
    fun create(file: File): LocalLlmBackend? {
        val extension = file.extension.lowercase()
        return when (extension) {
            "gguf" -> GgufLlamaCppBackend(context)
            else -> null
        }
    }
}
```

- [ ] **Step 3: Create the first real backend implementation skeleton**

Create `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt` with this content:

```kotlin
package com.example.note_secret_search

import android.content.Context
import io.github.ljcamargo.llamacpp.LlamaHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import java.io.File

class GgufLlamaCppBackend(
    private val context: Context,
) : LocalLlmBackend {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val eventFlow = MutableSharedFlow<LlamaHelper.LLMEvent>(
        replay = 0,
        extraBufferCapacity = 64,
    )
    private val llamaHelper = LlamaHelper(
        contentResolver = context.contentResolver,
        scope = scope,
        sharedFlow = eventFlow,
    )

    override fun inspect(file: File): LocalLlmInspectResult {
        if (!file.exists()) {
            return LocalLlmInspectResult(
                supported = false,
                reason = "模型文件不存在。",
            )
        }

        return if (file.extension.lowercase() == "gguf") {
            LocalLlmInspectResult(
                supported = true,
                reason = "检测到 GGUF 模型文件，可继续进行 runtime 校验。",
            )
        } else {
            LocalLlmInspectResult(
                supported = false,
                reason = "当前仅支持 GGUF 模型文件。",
            )
        }
    }

    override fun load(modelId: String, file: File): LocalLlmBackendSession {
        val contextId = runBlocking {
            var loadedContextId: Int? = null
            llamaHelper.load(
                path = file.absolutePath,
                contextLength = 2048,
            ) { id ->
                loadedContextId = id
            }
            loadedContextId ?: throw IllegalStateException("LlamaHelper.load() did not return a context id.")
        }
        return LocalLlmBackendSession(
            modelId = modelId,
            modelPath = file.absolutePath,
            backendName = "gguf-llama-cpp",
            handle = contextId,
        )
    }

    override fun generate(
        session: LocalLlmBackendSession,
        prompt: String,
        maxTokens: Int,
    ): LocalLlmGenerateResult {
        require(prompt.isNotBlank()) { "Prompt must not be blank." }
        return runBlocking {
            llamaHelper.predict(prompt)
            val event = eventFlow.first { candidate ->
                candidate is LlamaHelper.LLMEvent.Done || candidate is LlamaHelper.LLMEvent.Error
            }
            when (event) {
                is LlamaHelper.LLMEvent.Done -> {
                    val text = event.text.trim()
                    require(text.isNotBlank()) { "Backend returned empty text." }
                    LocalLlmGenerateResult(
                        text = text,
                        finishReason = "stop",
                    )
                }

                is LlamaHelper.LLMEvent.Error -> {
                    throw IllegalStateException(event.error)
                }

                else -> throw IllegalStateException("Unexpected llama helper event.")
            }
        }
    }

    override fun release(session: LocalLlmBackendSession) {
        llamaHelper.abort()
        llamaHelper.release()
        scope.cancel()
    }
}
```

- [ ] **Step 4: Run Flutter analyze to verify the new Android files integrate cleanly**

Run:

```powershell
flutter analyze
```

Expected:

- Dart analysis passes.
- No file reference/import errors are introduced.

- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/kotlin/com/example/note_secret_search/LlmBackendFactory.kt android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt
git commit -m "feat: add android gguf llm backend factory"
```

---

## Task 4: Refactor `LocalLlmRuntime` from stub into orchestration facade

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`

- [ ] **Step 1: Replace the `File` session type with `LocalLlmBackendSession` and inject the backend factory**

Update the constructor and properties in `LocalLlmRuntime.kt` to this:

```kotlin
class LocalLlmRuntime(
    private val context: Context,
    private val sessionManager: LlmModelSessionManager<LocalLlmBackendSession>,
) {
    private val backendFactory = LlmBackendFactory(context)
```

- [ ] **Step 2: Rewrite `inspectModel()` to use real backend selection semantics**

Replace `inspectModel()` with this implementation:

```kotlin
fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> {
    val file = File(modelPath)
    if (!file.exists()) {
        return runtimeState(
            status = "missing",
            reason = "当前本地 LLM 模型文件缺失，请重新下载或切换模型。",
            modelPath = modelPath,
            runtime = "none",
        )
    }

    val backend = backendFactory.create(file)
        ?: return runtimeState(
            status = "degraded",
            reason = "当前模型格式暂无可用 Android 本地推理 backend。",
            modelPath = modelPath,
            runtime = "unsupported",
        )

    val inspect = backend.inspect(file)
    if (!inspect.supported) {
        return runtimeState(
            status = "degraded",
            reason = inspect.reason,
            modelPath = modelPath,
            runtime = "unsupported",
        )
    }

    return runtimeState(
        status = "installed_unverified",
        reason = inspect.reason,
        modelPath = modelPath,
        runtime = "candidate",
    )
}
```

- [ ] **Step 3: Rewrite `ensureModelReady()` to perform real load + probe**

Replace `ensureModelReady()` with this implementation:

```kotlin
fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> {
    val file = File(modelPath)
    if (!file.exists()) {
        return runtimeState(
            status = "missing",
            reason = "当前本地 LLM 模型文件缺失，请重新下载或切换模型。",
            modelPath = modelPath,
            runtime = "none",
        )
    }

    val backend = backendFactory.create(file)
        ?: return runtimeState(
            status = "degraded",
            reason = "当前模型格式暂无可用 Android 本地推理 backend。",
            modelPath = modelPath,
            runtime = "unsupported",
        )

    return try {
        val session = sessionManager.get(modelId)
            ?: backend.load(modelId, file).also { created ->
                sessionManager.replace(modelId, created) { existing ->
                    backend.release(existing)
                }
            }

        val probe = backend.generate(session, "你好", maxTokens = 8)
        if (probe.text.isBlank()) {
            throw IllegalStateException("Backend returned empty text during readiness probe.")
        }

        runtimeState(
            status = "ready",
            reason = "本地 LLM runtime 已通过真实生成校验。",
            modelPath = modelPath,
            runtime = session.backendName,
        )
    } catch (error: Throwable) {
        sessionManager.release(modelId) { existing ->
            try {
                backend.release(existing)
            } catch (_: Throwable) {
            }
        }
        runtimeState(
            status = "degraded",
            reason = "模型已安装但当前不可运行：${error.message ?: "unknown error"}",
            modelPath = modelPath,
            runtime = "failed",
        )
    }
}
```

- [ ] **Step 4: Rewrite `generateText()` and `releaseModel()` to use the backend session**

Replace those methods with this code:

```kotlin
fun generateText(
    modelId: String,
    modelPath: String,
    prompt: String,
    usedPrivateContext: Boolean,
): Map<String, Any?> {
    require(prompt.isNotBlank()) { "Prompt must not be blank." }

    val ready = ensureModelReady(modelId, modelPath)
    if (ready["status"] != "ready") {
        throw IllegalStateException(ready["reason"] as? String ?: "LLM runtime is not ready.")
    }

    val file = File(modelPath)
    val backend = backendFactory.create(file)
        ?: throw IllegalStateException("No Android local LLM backend is available.")
    val session = sessionManager.get(modelId)
        ?: throw IllegalStateException("LLM session was not prepared.")

    return try {
        val result = backend.generate(session, prompt.trim(), maxTokens = 256)
        mapOf(
            "text" to result.text,
            "finishReason" to result.finishReason,
            "usedPrivateContext" to usedPrivateContext,
            "status" to "ready",
            "reason" to "本地 LLM runtime 已完成真实生成。",
            "checkedAt" to System.currentTimeMillis(),
            "modelPath" to modelPath,
            "runtime" to session.backendName,
            "contextPackage" to context.packageName,
        )
    } catch (error: Throwable) {
        sessionManager.release(modelId) { existing ->
            try {
                backend.release(existing)
            } catch (_: Throwable) {
            }
        }
        throw IllegalStateException(error.message ?: "Local LLM generation failed.")
    }
}

fun releaseModel(modelId: String) {
    val session = sessionManager.get(modelId) ?: return
    val backend = backendFactory.create(File(session.modelPath)) ?: run {
        sessionManager.release(modelId) { }
        return
    }
    sessionManager.release(modelId) { existing -> backend.release(existing) }
}
```

- [ ] **Step 5: Replace the old `runtimeState()` helper with the new runtime-aware version**

Update the helper to:

```kotlin
private fun runtimeState(
    status: String,
    reason: String,
    modelPath: String,
    runtime: String,
): Map<String, Any?> {
    return mapOf(
        "ready" to (status == "ready"),
        "status" to status,
        "reason" to reason,
        "checkedAt" to System.currentTimeMillis(),
        "modelPath" to modelPath,
        "runtime" to runtime,
        "supportsGeneration" to (status == "ready"),
        "contextPackage" to context.packageName,
    )
}
```

- [ ] **Step 6: Run Flutter analyze and the focused runtime/provider tests**

Run:

```powershell
flutter analyze
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart
```

Expected:

- Analyze passes.
- The truthful-state tests from Task 1 now pass.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt
git commit -m "feat: refactor android llm runtime facade"
```

---

## Task 5: Validate and harden the first real backend generation path

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt`
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`

- [ ] **Step 1: Verify `LlamaHelper` loading and prediction are bound to app-private GGUF paths**

Review and, if needed, adjust `GgufLlamaCppBackend.kt` so that:

- `llamaHelper.load(path = file.absolutePath, contextLength = 2048)` loads the app-private GGUF file path created by the existing model download flow;
- `llamaHelper.predict(prompt)` is only called after a successful `load()`;
- `LlamaHelper.LLMEvent.Done` provides the final generated text used to build `LocalLlmGenerateResult`;
- `LlamaHelper.LLMEvent.Error` throws an exception that propagates back to `LocalLlmRuntime`.

No placeholder or dummy generation path may remain.

- [ ] **Step 2: Ensure `release()` actually frees backend resources safely**

Keep `release()` non-empty and verify it calls, in order:

```kotlin
llamaHelper.abort()
llamaHelper.release()
scope.cancel()
```

If that ordering causes reuse issues during implementation, move scope ownership so each loaded session gets its own helper/scope pair, but do not regress to a no-op release.

- [ ] **Step 3: Verify there is no stub marker left in Android LLM generation code**

Run:

```powershell
flutter analyze
```

Expected:

- Analyze passes.
- The Android generation path no longer contains `[LOCAL_LLM_STUB]` in source.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt android/app/build.gradle.kts
git commit -m "feat: wire real android local llm generation"
```

---

## Task 6: Propagate truthful runtime behavior through Flutter orchestration and persistence tests

**Files:**
- Modify: `test/features/ai_chat/application/ai_chat_providers_test.dart`
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`
- Modify: `test/features/ai_models/application/model_selection_providers_test.dart`

- [ ] **Step 1: Add a failing orchestration test for runtime failure persistence**

Add this test to `test/features/ai_chat/application/ai_chat_providers_test.dart`:

```dart
test('controller keeps failed assistant message persistence when runtime reports degraded generation', () async {
  final fakeRepository = _FakeChatSessionRepository();
  final fakeLlmEngine = _ThrowingLlmEngine(message: '真实本地 LLM 生成失败');
  final container = ProviderContainer(
    overrides: [
      localLlmReadinessProvider.overrideWith(
        (ref) async => const LocalLlmReadiness(
          ready: true,
          reason: 'ready',
          activeModel: _llmModel,
          runtimeState: LlmRuntimeState(
            ready: true,
            reason: 'ready',
            status: LlmRuntimeStatus.ready,
          ),
        ),
      ),
      chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
      llmEngineProvider.overrideWithValue(fakeLlmEngine),
    ],
  );

  addTearDown(container.dispose);

  final controller = container.read(freeChatControllerProvider.notifier);
  await controller.send('运行真实本地 LLM');

  expect(fakeRepository.savedMessages.last.role, ChatStoredMessageRole.system);
  expect(fakeRepository.savedMessages.last.status, ChatStoredMessageStatus.failed);
  expect(fakeRepository.savedMessages.last.content, contains('真实本地 LLM 生成失败'));
});
```

- [ ] **Step 2: Add a failing download verification test for degraded runtime after LLM download**

Add this test to `test/features/ai_models/application/model_download_providers_test.dart`:

```dart
test('startDownload keeps llm model disabled when runtime verification returns degraded', () async {
  // follow the existing controller test setup pattern in this file
  // assert that a downloaded llm registry entry remains disabled when
  // mapLlmRuntimeState(...) resolves to LlmRuntimeStatus.degraded
});
```

Use the exact local file path and task setup pattern already used by the existing tests in this file; only the runtime result should differ.

- [ ] **Step 3: Add a failing model-selection self-healing test for truthful degraded state**

Add this test to `test/features/ai_models/application/model_selection_providers_test.dart`:

```dart
test('activeLocalLlmModelProvider self-heals when runtime probe fails after selection', () async {
  SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
      modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
      llmRuntimeStatesProvider.overrideWith(
        (ref) async => {
          'llm-1': const LlmRuntimeState(
            ready: false,
            reason: '真实 probe failed',
            status: LlmRuntimeStatus.degraded,
          ),
        },
      ),
    ],
  );

  addTearDown(container.dispose);

  final model = await container.read(activeLocalLlmModelProvider.future);
  expect(model, isNull);
});
```

- [ ] **Step 4: Run the focused Flutter regression suite**

Run:

```powershell
flutter test test/features/ai_chat/application/ai_chat_providers_test.dart
flutter test test/features/ai_models/application/model_download_providers_test.dart
flutter test test/features/ai_models/application/model_selection_providers_test.dart
```

Expected:

- All three suites pass with truthful runtime behavior.

- [ ] **Step 5: Commit**

```bash
git add test/features/ai_chat/application/ai_chat_providers_test.dart test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/application/model_selection_providers_test.dart
git commit -m "test: cover truthful local llm runtime behavior"
```

---

## Task 7: Full verification and implementation handoff for the Android local LLM backend

**Files:**
- Review: `docs/superpowers/specs/2026-04-26-android-local-llm-backend-design.md`
- Review: `docs/superpowers/plans/2026-04-25-local-llm-first-batch.md`
- Review: all files changed by Tasks 1-6

- [ ] **Step 1: Run the focused local LLM verification suite**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart
flutter test test/features/ai_chat/application/ai_chat_providers_test.dart
flutter test test/features/ai_models/application/model_download_providers_test.dart
flutter test test/features/ai_models/application/model_selection_providers_test.dart
flutter test test/features/ai_models/presentation/model_management_page_test.dart
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
flutter analyze
```

Expected:

- All tests PASS.
- Analyzer clean.

- [ ] **Step 2: Verify the stub path is gone manually**

Review `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt` and `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt` and confirm:

- `generateText()` no longer emits `[LOCAL_LLM_STUB]`
- `ensureModelReady()` establishes `ready` through real probe generation
- `releaseModel()` is not a no-op

- [ ] **Step 3: Verify spec coverage manually**

Check the spec sections against the completed work:

1. Backend abstraction/factory present.
2. `LocalLlmRuntime` is a facade, not a stub generator.
3. First real backend exists.
4. `/models` and `/ai/chat` consume truthful runtime states.
5. Errors still persist to assistant/system messages where appropriate.

If any item is not satisfied, add a follow-up task before declaring the work complete.

- [ ] **Step 4: Prepare handoff summary**

Write a short summary that lists:

```text
- Which Android local LLM backend was integrated
- How readiness is now established
- How generation/release behave
- What remains intentionally deferred (streaming, advanced sampling, multi-model caching, performance tuning)
```

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: add real android local llm backend"
```

---

## Self-Review

### Spec coverage

- Backend abstraction/factory: Tasks 2-4.
- `LocalLlmRuntime` facade behavior: Task 4.
- First real backend: Task 3 + Task 5.
- Truthful runtime propagation to Flutter/model management/chat: Tasks 1, 4, 6.
- Full verification and handoff: Task 7.

### Placeholder scan

- The plan now fixes the first backend path to `io.github.ljcamargo:llamacpp-kotlin:0.2.0` with `LlamaHelper` as the integration API.
- Remaining implementation risk is limited to runtime integration behavior on actual Android devices, not to unresolved dependency or API selection.

### Type consistency

- `LocalLlmBackend`, `LocalLlmBackendSession`, `LlmBackendFactory`, `LocalLlmRuntime`, `LlmRuntimeStatus`, and `LlmRuntimeState` names are used consistently throughout this plan.
