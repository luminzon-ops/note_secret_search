# Huawei Local LLM Native Crash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/ai/chat` produce a first stable on-device local LLM reply on Huawei `SPN_AL00` without disabling local generation.

**Status (2026-05-17):** ✅ **Achieved on Huawei `SPN-AL00` real device.** Both `SmolLM2 360M Instruct Local` and `Qwen2.5 0.5B Instruct Local` now return non-empty first replies (13.9 s / 15.7 s, 217 / 98 chars) without any native crash. See `第一阶段产品进度报告.md` §13 for full evidence and `llm_smollm_run_bypass.log` / `llm_qwen_run_bypass.log` for raw logcat. The root cause turned out to be **not** the `_v8_2_fp16` SIMD variant alone — it was the AAR's `LlamaHelper.predict()` calling `LlamaAndroid.launchCompletion` **without `n_predict`**, causing unbounded native generation that segfaults / bus-faults / aborts at `Java_org_nehuatl_llamacpp_LlamaContext_doCompletion+1284` on Kirin 990 Cortex-A77. Fix applied: (A) `packaging.jniLibs.pickFirsts` overrides the crashing `_v8_2_fp16*.so` filenames with v8 baseline content + (B) `AndroidLlamaHelperClient.predict` reflects out `LlamaAndroid` and calls `launchCompletion(contextId, {prompt, emit_partial_completion, n_predict=96, temperature=0.7, top_k=40, top_p=0.9, seed=42, stop=[</s>,<|im_end|>,<|endoftext|>]})` directly + (C) 45 s timeout + heartbeat + device fingerprint diagnostics.

**Architecture:** First fix the app-owned generation contract by threading an explicit conservative local-generation policy from Dart to Kotlin, and by making the Kotlin runtime apply the same policy family to both readiness/load and generation. If Huawei still aborts after that contract is explicit and test-covered, keep a second-stage fallback that routes Huawei to a more conservative packaged native variant instead of disabling local LLM.

**Tech Stack:** Flutter, Dart, Riverpod, MethodChannel bridge, Kotlin, Android unit tests, existing `llamacpp-kotlin-0.2.0-huawei-safe.aar`, Flutter tests, `flutter analyze`, Gradle `:app` unit tests, ADB device verification.

---

## File Structure / Responsibilities

### Existing files to modify

- `lib/features/ai_chat/domain/llm_engine.dart`
  - Extend the local inference request with explicit generation-policy fields owned by the app.

- `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`
  - Send the new local-generation policy fields over the method channel.

- `lib/features/ai_chat/infrastructure/local_llm_engine.dart`
  - Serialize the new request fields into `generateText` bridge calls and keep response mapping unchanged.

- `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt`
  - Parse the new method-channel arguments and pass them into runtime generation.

- `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`
  - Build a Huawei-aware generation policy, log it, and pass it into the backend while preserving the existing session lifecycle.

- `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt`
  - Replace ad hoc generation literals with a structured generation config, keep `contextLength = 1024` sourced from that config family, and enforce prompt/output bounds before native `predict()`.

- `android/app/src/test/kotlin/com/example/note_secret_search/GgufLlamaCppBackendTest.kt`
  - Add Kotlin test-first coverage for conservative generation config, prompt truncation, and request logging metadata.

- `test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart`
  - Add Dart test-first coverage for forwarding conservative generation-policy fields into the bridge.

- `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`
  - Add method-channel bridge test coverage for the new generate payload shape.

- `android/app/build.gradle.kts`
  - Keep the current AAR dependency, but annotate and prepare the packaging boundary for a future conservative Huawei-only variant swap if needed.

- `android/app/src/main/kotlin/com/example/note_secret_search/LlmBackendFactory.kt`
  - Preserve the Huawei backend allowlist while adding any minimal selection hook or log boundary needed for a future conservative fallback route.

### Existing files to validate but not structurally redesign

- `lib/features/ai_chat/application/ai_chat_providers.dart`
  - Validate that local generation still flows through the existing orchestrator with the expanded request payload.

- `test/features/ai_chat/presentation/ai_chat_page_test.dart`
  - Keep existing local-first UI behavior passing after request-shape expansion.

---

## Task 1: Add failing Dart tests for explicit local-generation policy forwarding

**Files:**
- Modify: `lib/features/ai_chat/domain/llm_engine.dart`
- Modify: `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`
- Modify: `lib/features/ai_chat/infrastructure/local_llm_engine.dart`
- Test: `test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart`
- Test: `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`

- [ ] **Step 1: Extend the failing local engine test with explicit policy expectations**

Update `test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart` so the request includes conservative Huawei fields:

```dart
final response = await engine.generate(
  const LlmInferenceRequest(
    model: _installedLlmModel,
    prompt: '请总结这段内容。',
    usedPrivateContext: true,
    maxOutputTokens: 96,
    maxPromptChars: 1200,
    contextLength: 1024,
    conservativeMode: true,
  ),
);

expect(
  bridge.generateTextCalls.single,
  const _GenerateTextCall(
    modelId: 'qwen-local',
    modelPath: '/data/user/0/app/files/models/qwen.gguf',
    prompt: '请总结这段内容。',
    usedPrivateContext: true,
    maxOutputTokens: 96,
    maxPromptChars: 1200,
    contextLength: 1024,
    conservativeMode: true,
  ),
);
```

- [ ] **Step 2: Run the targeted Dart test and verify it fails for missing fields**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart --plain-name "generate maps bridge payload into inference response"
```

Expected:

- The test fails because `LlmInferenceRequest` and `_GenerateTextCall` do not yet contain the new policy fields.

- [ ] **Step 3: Extend the failing method-channel test with the new payload shape**

Update `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`:

```dart
expect(call.arguments, <String, Object?>{
  'modelId': 'phi-mini',
  'modelPath': '/data/user/0/app/files/models/phi.gguf',
  'prompt': '你好',
  'usedPrivateContext': false,
  'maxOutputTokens': 96,
  'maxPromptChars': 1200,
  'contextLength': 1024,
  'conservativeMode': true,
});

final result = await bridge.generateText(
  modelId: 'phi-mini',
  modelPath: '/data/user/0/app/files/models/phi.gguf',
  prompt: '你好',
  usedPrivateContext: false,
  maxOutputTokens: 96,
  maxPromptChars: 1200,
  contextLength: 1024,
  conservativeMode: true,
);
```

- [ ] **Step 4: Run the targeted method-channel test and verify it fails for the missing bridge arguments**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart --plain-name "maps generateText payload into LlmInferenceResponse-compatible map"
```

Expected:

- The test fails because `MethodChannelLlmRuntimeBridge.generateText()` does not yet accept or send the new arguments.

- [ ] **Step 5: Implement the minimal Dart request and bridge contract**

Update `lib/features/ai_chat/domain/llm_engine.dart`:

```dart
class LlmInferenceRequest {
  const LlmInferenceRequest({
    required this.model,
    required this.prompt,
    required this.usedPrivateContext,
    this.maxOutputTokens = 96,
    this.maxPromptChars = 1200,
    this.contextLength = 1024,
    this.conservativeMode = true,
  });

  final ModelRegistryEntry model;
  final String prompt;
  final bool usedPrivateContext;
  final int maxOutputTokens;
  final int maxPromptChars;
  final int contextLength;
  final bool conservativeMode;
}
```

Update `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`:

```dart
Future<Map<String, dynamic>> generateText({
  required String modelId,
  required String modelPath,
  required String prompt,
  required bool usedPrivateContext,
  required int maxOutputTokens,
  required int maxPromptChars,
  required int contextLength,
  required bool conservativeMode,
});
```

and send these fields in `invokeMapMethod`.

Update `lib/features/ai_chat/infrastructure/local_llm_engine.dart`:

```dart
final result = await _bridge.generateText(
  modelId: request.model.id,
  modelPath: path,
  prompt: request.prompt,
  usedPrivateContext: request.usedPrivateContext,
  maxOutputTokens: request.maxOutputTokens,
  maxPromptChars: request.maxPromptChars,
  contextLength: request.contextLength,
  conservativeMode: request.conservativeMode,
);
```

- [ ] **Step 6: Run the focused Dart tests and verify green**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart
```

Expected:

- Both files pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/ai_chat/domain/llm_engine.dart lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart lib/features/ai_chat/infrastructure/local_llm_engine.dart test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart test/features/ai_chat/infrastructure/local_llm_engine_test.dart
git commit -m "feat: add explicit local llm generation policy payload"
```

---

## Task 2: Add failing Kotlin tests for Huawei conservative generation policy

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt`
- Test: `android/app/src/test/kotlin/com/example/note_secret_search/GgufLlamaCppBackendTest.kt`

- [ ] **Step 1: Add a failing Kotlin test that load and generate are derived from the same policy family**

Append this test to `android/app/src/test/kotlin/com/example/note_secret_search/GgufLlamaCppBackendTest.kt`:

```kotlin
@Test
fun `huawei conservative generation config keeps context length and disables partial completion`() = runBlocking {
    val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    val events = MutableSharedFlow<LlamaHelper.LLMEvent>(replay = 0, extraBufferCapacity = 1)
    val helper = RecordingLlamaHelperClient(events)
    val backend = GgufLlamaCppBackend(
        helper = helper,
        predictionScope = predictionScope,
        eventFlow = events,
    )
    val session = backend.load(
        modelId = "smollm-huawei",
        file = File("/data/user/0/com.example.note_secret_search/files/models/smollm.gguf"),
    )

    backend.generate(
        session = session,
        prompt = "hello-stability-check",
        maxTokens = 96,
        config = LocalLlmGenerationConfig(
            contextLength = 1024,
            maxOutputTokens = 96,
            maxPromptChars = 1200,
            conservativeMode = true,
            emitPartialCompletion = false,
        ),
    )

    assertEquals(1024, helper.lastContextLength)
    assertFalse(helper.lastEmitPartialCompletion)
    assertEquals(96, helper.lastRequestedMaxTokens)
    predictionScope.cancel()
}
```

- [ ] **Step 2: Add a failing Kotlin test for prompt truncation before predict**

Append this test to the same file:

```kotlin
@Test
fun `generate truncates prompt to conservative maxPromptChars before native predict`() = runBlocking {
    val predictionScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    val events = MutableSharedFlow<LlamaHelper.LLMEvent>(replay = 0, extraBufferCapacity = 1)
    val helper = RecordingLlamaHelperClient(events)
    val backend = GgufLlamaCppBackend(
        helper = helper,
        predictionScope = predictionScope,
        eventFlow = events,
    )
    val session = LocalLlmBackendSession(
        modelId = "phi-local",
        modelPath = "/data/user/0/com.example.note_secret_search/files/models/smollm.gguf",
        backendName = "gguf-llama-cpp",
        handle = 7L,
        backend = backend,
    )

    backend.generate(
        session = session,
        prompt = "a".repeat(20),
        maxTokens = 96,
        config = LocalLlmGenerationConfig(
            contextLength = 1024,
            maxOutputTokens = 96,
            maxPromptChars = 8,
            conservativeMode = true,
            emitPartialCompletion = false,
        ),
    )

    assertEquals("aaaaaaaa", helper.lastPrompt)
    predictionScope.cancel()
}
```

- [ ] **Step 3: Run the focused Android unit test file and verify it fails for missing generation config support**

Run:

```powershell
./gradlew :app:testDebugUnitTest --tests "com.example.note_secret_search.GgufLlamaCppBackendTest"
```

Expected:

- The test fails because `LocalLlmGenerationConfig`, `config = ...`, and helper tracking fields do not yet exist.

- [ ] **Step 4: Implement the minimal Kotlin generation config model and backend support**

Add this to `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt` near the backend types:

```kotlin
internal data class LocalLlmGenerationConfig(
    val contextLength: Int,
    val maxOutputTokens: Int,
    val maxPromptChars: Int,
    val conservativeMode: Boolean,
    val emitPartialCompletion: Boolean,
)
```

Change `generate(...)` to accept the config:

```kotlin
override fun generate(
    session: LocalLlmBackendSession,
    prompt: String,
    maxTokens: Int,
    config: LocalLlmGenerationConfig,
): LocalLlmGenerateResult
```

and enforce the app-owned bounds before `helper.predict(...)`:

```kotlin
val boundedPrompt = prompt.trim().take(config.maxPromptChars)
helper.predict(boundedPrompt, emitPartialCompletion = config.emitPartialCompletion)
```

Extend `RecordingLlamaHelperClient` with:

```kotlin
var lastRequestedMaxTokens: Int = 0
var lastPrompt: String = ""
```

and capture them in the test fake before emitting `Done`.

- [ ] **Step 5: Add a Huawei policy builder to `LocalLlmRuntime.kt`**

Introduce a single policy constructor in `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`:

```kotlin
internal fun buildLocalGenerationConfig(
    manufacturer: String,
    prompt: String,
    requestedMaxTokens: Int,
): LocalLlmGenerationConfig {
    val isHuaweiFamily = manufacturer.trim().equals("huawei", ignoreCase = true) ||
        manufacturer.trim().equals("honor", ignoreCase = true)
    return if (isHuaweiFamily) {
        LocalLlmGenerationConfig(
            contextLength = HUAWEI_SAFE_CONTEXT_LENGTH,
            maxOutputTokens = requestedMaxTokens.coerceAtMost(96),
            maxPromptChars = 1200,
            conservativeMode = true,
            emitPartialCompletion = false,
        )
    } else {
        LocalLlmGenerationConfig(
            contextLength = HUAWEI_SAFE_CONTEXT_LENGTH,
            maxOutputTokens = requestedMaxTokens,
            maxPromptChars = 2400,
            conservativeMode = false,
            emitPartialCompletion = false,
        )
    }
}
```

- [ ] **Step 6: Run the focused Android unit test file and verify green**

Run:

```powershell
./gradlew :app:testDebugUnitTest --tests "com.example.note_secret_search.GgufLlamaCppBackendTest"
```

Expected:

- `GgufLlamaCppBackendTest` passes.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt android/app/src/test/kotlin/com/example/note_secret_search/GgufLlamaCppBackendTest.kt
git commit -m "fix: add huawei conservative local generation policy"
```

---

## Task 3: Thread the conservative generation policy through the Android runtime boundary

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt`
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`
- Modify: `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`

- [ ] **Step 1: Add the failing runtime-plugin parsing test mentally through compile errors first**

The current file has no dedicated plugin unit test, so use a compile-driven step: update the Dart and Kotlin signatures first, then let Kotlin/Dart compilers force every callsite update.

Target signatures:

```kotlin
fun generateText(
    modelId: String,
    modelPath: String,
    prompt: String,
    usedPrivateContext: Boolean,
    maxOutputTokens: Int,
    maxPromptChars: Int,
    contextLength: Int,
    conservativeMode: Boolean,
): Map<String, Any?>
```

- [ ] **Step 2: Update `LlmRuntimePlugin.kt` argument parsing**

In the `generateText` branch, add:

```kotlin
val maxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 96
val maxPromptChars = call.argument<Int>("maxPromptChars") ?: 1200
val contextLength = call.argument<Int>("contextLength") ?: HUAWEI_SAFE_CONTEXT_LENGTH
val conservativeMode = call.argument<Boolean>("conservativeMode") ?: true
```

and pass them to `runtime.generateText(...)`.

- [ ] **Step 3: Update `LocalLlmRuntime.generateText()` to accept explicit request policy**

Change the method signature in `LocalLlmRuntime.kt`:

```kotlin
override fun generateText(
    modelId: String,
    modelPath: String,
    prompt: String,
    usedPrivateContext: Boolean,
    maxOutputTokens: Int,
    maxPromptChars: Int,
    contextLength: Int,
    conservativeMode: Boolean,
): Map<String, Any?>
```

Derive the effective runtime config from the incoming request plus manufacturer:

```kotlin
val config = buildLocalGenerationConfig(
    manufacturer = android.os.Build.MANUFACTURER,
    prompt = prompt,
    requestedMaxTokens = maxOutputTokens,
).copy(
    contextLength = contextLength,
    maxPromptChars = maxPromptChars,
    conservativeMode = conservativeMode,
)
```

- [ ] **Step 4: Pass the new config into backend generation and include it in logs**

Add a structured log before generation:

```kotlin
logInfo(
    "generateText effective-config modelId=$modelId contextLength=${config.contextLength} " +
    "maxOutputTokens=${config.maxOutputTokens} maxPromptChars=${config.maxPromptChars} " +
    "conservativeMode=${config.conservativeMode} usedPrivateContext=$usedPrivateContext"
)
```

and call:

```kotlin
val result = session.backend.generate(
    session,
    prompt.trim(),
    maxTokens = config.maxOutputTokens,
    config = config,
)
```

- [ ] **Step 5: Run compile-oriented validation**

Run:

```powershell
flutter analyze
./gradlew :app:testDebugUnitTest --tests "com.example.note_secret_search.GgufLlamaCppBackendTest"
```

Expected:

- Flutter analysis is clean.
- Android focused unit tests still pass after the signature changes.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart
git commit -m "fix: thread local llm generation policy through runtime"
```

---

## Task 4: Add request-scoped observability for Huawei crash correlation

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt`
- Modify: `test/features/ai_chat/presentation/ai_chat_page_test.dart`

- [ ] **Step 1: Add a request correlation id generator in `LocalLlmRuntime.kt`**

Create a tiny helper near the runtime class:

```kotlin
internal fun newGenerationRequestId(): String = System.currentTimeMillis().toString()
```

- [ ] **Step 2: Include the request id and session-reuse state in runtime logs**

Log before `ensureModelReady()` and before `session.backend.generate(...)`:

```kotlin
val requestId = newGenerationRequestId()
logInfo("generateText start requestId=$requestId modelId=$modelId reusedSession=$failedWhileReusingExistingSession")
```

and in the backend:

```kotlin
logInfo("backend generate requestId=$requestId promptChars=${boundedPrompt.length} maxTokens=${config.maxOutputTokens}")
```

If `GgufLlamaCppBackend.kt` does not currently own a logger helper, add one following the `LocalLlmRuntime` logging pattern.

- [ ] **Step 3: Return diagnostic fields in success payloads for test visibility**

Extend the map returned by `LocalLlmRuntime.generateText()`:

```kotlin
"requestId" to requestId,
"contextLength" to config.contextLength,
"maxOutputTokens" to config.maxOutputTokens,
"maxPromptChars" to config.maxPromptChars,
"conservativeMode" to config.conservativeMode,
```

- [ ] **Step 4: Extend the local engine generate test to assert the diagnostic payload is ignored safely by Dart response mapping**

Update `test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart` fake payload:

```dart
generateTextResult: {
  'text': '这是 Android 本地 LLM 的回答。',
  'finishReason': 'stop',
  'usedPrivateContext': true,
  'requestId': 'req-1',
  'contextLength': 1024,
  'maxOutputTokens': 96,
  'maxPromptChars': 1200,
  'conservativeMode': true,
},
```

The expectation remains the same: Dart should still map only `text`, `finishReason`, and `usedPrivateContext` into `LlmInferenceResponse` without breaking.

- [ ] **Step 5: Run relevant tests and analysis**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
flutter analyze
```

Expected:

- Both Flutter test files pass.
- Analysis is clean.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart test/features/ai_chat/presentation/ai_chat_page_test.dart
git commit -m "chore: add local llm generation diagnostics"
```

---

## Task 5: Prepare the conservative native-variant fallback boundary

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/LlmBackendFactory.kt`
- Modify: `docs/superpowers/specs/2026-05-13-huawei-local-llm-native-crash-design.md`

- [ ] **Step 1: Add a build comment documenting the current AAR boundary**

In `android/app/build.gradle.kts`, annotate the dependency:

```kotlin
// Current default Huawei-safe package. If Huawei still aborts after app-owned
// conservative generation policy fixes, swap this boundary to a more
// conservative variant package rather than disabling local generation.
implementation(files("../third_party/llamacpp-kotlin-0.2.0-huawei-safe.aar"))
```

- [ ] **Step 2: Add a minimal factory log boundary for variant-related investigation**

In `LlmBackendFactory.kt`, add a log before backend creation:

```kotlin
android.util.Log.i(
    "LlmBackendFactory",
    "create gguf backend manufacturer=${android.os.Build.MANUFACTURER} hasHuaweiSafeVariant=$HAS_HUAWEI_SAFE_GGUF_VARIANT"
)
```

Keep the current allow/block logic unchanged in this task.

- [ ] **Step 3: Re-read the design spec and append the exact second-stage fallback rule if needed**

If the implementation reveals that the wrapped AAR still crashes after conservative request-policy fixes, append this sentence to the spec’s variant section:

```markdown
The first fallback after policy-level fixes is to route Huawei builds to a more conservative packaged native variant (`librnllama.so` / `librnllama_v8.so`) rather than disabling local LLM or changing unrelated chat logic.
```

- [ ] **Step 4: Run lightweight verification**

Run:

```powershell
flutter analyze
```

Expected:

- Analysis stays clean because this task adds only comments and logging.

- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/kotlin/com/example/note_secret_search/LlmBackendFactory.kt docs/superpowers/specs/2026-05-13-huawei-local-llm-native-crash-design.md
git commit -m "chore: document huawei local llm fallback boundary"
```

---

## Task 6: Run end-to-end verification on Huawei `SPN_AL00`

**Files:**
- Validate: `android/app/build.gradle.kts`
- Validate: `app-debug.apk`
- Validate: `llm_real_device_failure_log_utf8.txt`
- Validate: `llm_crash_context_utf8.txt`

- [ ] **Step 1: Run focused Flutter tests for the changed local-LLM bridge path**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_generate_test.dart
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected:

- All three files pass.

- [ ] **Step 2: Run focused Android unit tests for the backend policy path**

Run:

```powershell
./gradlew :app:testDebugUnitTest --tests "com.example.note_secret_search.GgufLlamaCppBackendTest"
```

Expected:

- The backend-policy tests pass.

- [ ] **Step 3: Run static verification and build the APK**

Run:

```powershell
flutter analyze
flutter build apk --debug
```

Expected:

- `flutter analyze` reports `No issues found`.
- `flutter build apk --debug` succeeds.

- [ ] **Step 4: Export and install the APK on Huawei**

Run:

```powershell
Copy-Item -LiteralPath "build\app\outputs\flutter-apk\app-debug.apk" -Destination "app-debug.apk" -Force
adb -s H8B4C19731000256 install -r "E:\Archive\Flutter\note_secret_search\app-debug.apk"
```

Expected:

- APK is refreshed at repo root.
- `adb install -r` reports `Success`.

- [ ] **Step 5: Reproduce the first local free-chat reply on Huawei and collect logs**

Manual device flow:

1. Unlock with PIN `1234`.
2. Open `/ai/chat`.
3. Confirm runtime banner still points to `SmolLM2 360M Instruct Local`.
4. Enter `自由聊天`.
5. Start a new session.
6. Send a short prompt such as `请用一句话介绍你自己。`.

Log collection commands:

```powershell
adb -s H8B4C19731000256 logcat -d > llm_real_device_failure_log_utf8.txt
adb -s H8B4C19731000256 shell pidof com.example.note_secret_search
```

Expected success state:

- The app stays alive.
- A local response is rendered.
- `pidof` returns a process id.

Expected fallback state if still failing:

- The app crashes again, but logs now include request policy details that justify escalating to the conservative native-variant fallback.

- [ ] **Step 6: Commit the implementation branch state only if the device verification is green**

```bash
git add .
git commit -m "fix: stabilize huawei local llm first response"
```

If device verification is still red, do **not** make this final success commit. Instead, stop after collecting the new evidence and open the second-stage conservative variant fallback task.

---

## Self-Review Summary

Spec coverage:

1. explicit generation-path contract — covered by Tasks 1–3
2. conservative Huawei policy — covered by Tasks 2–4
3. native-variant fallback boundary — covered by Task 5
4. real Huawei verification — covered by Task 6

Placeholder scan:

1. no `TBD` or `TODO` placeholders remain
2. all code-changing steps include concrete code or exact signatures
3. all verification steps include exact commands and expected outcomes

Type consistency:

1. `LlmInferenceRequest` gains `maxOutputTokens`, `maxPromptChars`, `contextLength`, and `conservativeMode`
2. `LlmRuntimeBridge.generateText()` and `LocalLlmRuntime.generateText()` use the same field names
3. `LocalLlmGenerationConfig` is the single Kotlin config object referenced across runtime and backend tasks

---

Plan complete and saved to `docs/superpowers/plans/2026-05-13-huawei-local-llm-native-crash.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
