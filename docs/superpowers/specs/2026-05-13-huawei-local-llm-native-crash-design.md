# Huawei Local LLM Native Crash Design

**Goal:** Stabilize the first real on-device local LLM response on Huawei `SPN_AL00` without disabling local generation, by fixing the generation-path contract and preserving a conservative native-variant fallback.

**Status:** User explicitly asked to continue development without pausing for approval. This design is therefore treated as the active working direction and is written to support immediate planning.

---

## 1. Problem Statement

The current local LLM flow no longer fails at installation, selection, or page wiring.

What is already proven:

1. Huawei `SPN_AL00` can install and run the debug APK.
2. `files/models` contains both `qwen2_5_0_5b_instruct_q4_k_m.gguf` and `smollm2_360m_instruct_q4_k_m.gguf`.
3. `flutter.ai.active_llm_model_id` points to `smollm2_360m_instruct_q4_k_m`.
4. `/ai/chat` shows `本地 LLM 模型已经就绪：SmolLM2 360M Instruct Local`.
5. The first free-chat request enters the real generation path and reaches `正在生成回答`.

The remaining blocker is narrower and more specific:

> The app aborts during the first real native text-generation path on Huawei Android 10, with tombstone evidence pointing to `base.apk!librnllama_v8_2_fp16.so`.

This is not a UI problem and not a generic “model missing” problem. It is a **native generation stability** problem.

---

## 2. Confirmed Evidence

### 2.1 Tombstone evidence

`llm_real_device_failure_log_utf8.txt` and `llm_crash_context_utf8.txt` show:

1. `Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE)`
2. crashing thread: `DefaultDispatch`
3. process: `com.example.note_secret_search`
4. native backtrace inside `librnllama_v8_2_fp16.so`
5. the abort happens only after the app has already entered the real generation phase

This strongly suggests a deliberate native abort path such as an internal assertion or invariant failure, not a pure Flutter exception.

### 2.2 AAR evidence

The bundled `android/third_party/llamacpp-kotlin-0.2.0-huawei-safe.aar` contains multiple arm64 variants:

1. `librnllama.so`
2. `librnllama_v8.so`
3. `librnllama_v8_2_fp16.so`
4. `librnllama_v8_2_fp16_dotprod.so`
5. `librnllama_v8_4_fp16_dotprod.so`
6. `librnllama_v8_4_fp16_dotprod_i8mm.so`

So “which variant is actually selected at runtime” is part of the debugging surface.

### 2.3 Native string evidence

String extraction from `librnllama_v8_2_fp16.so` shows high-signal failure strings including:

1. `LM_GGML_ASSERT(%s) failed`
2. `llama_decode() failed during prompt`
3. `llama_decode() failed during text generation`
4. `n_tokens_all <= cparams.n_batch`
5. `%s: n_batch and n_ubatch cannot both be zero`
6. `%s: llama_kv_cache_init() failed for self-attention cache`
7. `%s: not enough space in the context's memory pool`

This is important because it narrows the failure class to **decode-path or cache/path invariant failure**, not merely file-open failure.

### 2.4 Current repo behavior

From the current Kotlin and Dart code:

1. `GgufLlamaCppBackend.load()` calls `helper.load(path = ..., contextLength = HUAWEI_SAFE_CONTEXT_LENGTH)` with `HUAWEI_SAFE_CONTEXT_LENGTH = 1024`.
2. `GgufLlamaCppBackend.generate()` calls `helper.predict(prompt, emitPartialCompletion = false)`.
3. `generate()` does **not** pass `maxTokens`, `n_batch`, `n_threads`, `use_mmap`, `use_mlock`, or any other generation-path parameters.
4. `LlmInferenceRequest` currently carries only:
   - `model`
   - `prompt`
   - `usedPrivateContext`
5. `MethodChannelLlmRuntimeBridge.generateText()` currently sends only:
   - `modelId`
   - `modelPath`
   - `prompt`
   - `usedPrivateContext`

So the current code proves that **the Huawei-safe load configuration is not mirrored by a clearly defined Huawei-safe generation configuration**.

---

## 3. Root-Cause Ranking

### 3.1 Most likely: generation-path contract mismatch

This is the primary hypothesis.

The app currently treats `contextLength = 1024` and `emitPartialCompletion = false` as Huawei stability controls, but those controls are only partially enforced:

1. `contextLength` is applied at load time.
2. `emitPartialCompletion = false` is applied at predict time.
3. there is no single shared generation-policy object spanning Dart request → method channel → Kotlin runtime → backend → native helper.
4. generation-specific bounds such as prompt truncation, requested output size, reuse policy, or future batch-like settings do not have an explicit app-owned contract.

Why this ranks first:

1. device flow reaches ready state and only dies at first decode path;
2. native strings point to decode/cache/batch invariants;
3. current repo code leaves generation-path limits under-specified.

### 3.2 Second most likely: aggressive native variant selection on Huawei

This is the second hypothesis.

Even if the app passes a conservative context length, the runtime is still entering `librnllama_v8_2_fp16.so`. That may still be too aggressive for the real Huawei CPU feature set or vendor runtime behavior.

Why this ranks second:

1. the AAR bundles several variants, so selection matters;
2. external evidence for Android arm64 llama wrappers repeatedly shows crashes that differ between emulator and real hardware;
3. Huawei vendor CPU/runtime behavior may be less tolerant of fp16-optimized kernels than the generic `v8` path.

### 3.3 Third most likely: session lifecycle or first-generation warmup edge

This is the fallback hypothesis.

`LocalLlmRuntime.generateText()` always re-enters `ensureModelReady()` before real generation. The same logical model session may therefore cross several boundaries:

1. readiness probe or initial load
2. persisted session reuse
3. first real generation
4. abort/release cleanup after failure

If the wrapped helper expects a different lifecycle than the app currently assumes, the first decode path can expose it.

This ranks third because the existing evidence is stronger for parameter / variant issues than for race-only explanations.

---

## 4. Recommended Approach

### Recommended option

Use a **two-layer stabilization design**:

1. **Primary fix:** make generation-path settings explicit, app-owned, logged, and consistent across Dart → bridge → Kotlin → backend.
2. **Secondary fallback:** add Huawei-targeted observability and a controlled route to force a more conservative native variant if the explicit generation-policy fix is not sufficient.

This is the recommended option because it fixes the most likely root cause first while preserving a safe backup path that still keeps local generation enabled.

### Rejected alternatives

#### Alternative A: disable local LLM on Huawei

Rejected because the user explicitly set the success criterion to **“必须本地可生”**.

#### Alternative B: keep guessing native parameters ad hoc

Rejected because the current repo does not yet have a coherent generation-policy surface. Blind tweaking would change symptoms without making the system more understandable.

#### Alternative C: immediately swap the entire backend or remove the AAR

Rejected as a first move because the current code still contains unexplained mismatches in its own request contract. Replacing the backend first would skip the most valuable root-cause clarification step.

---

## 5. Design Overview

### 5.1 Introduce an explicit local generation policy

The app needs a single app-owned policy object for local generation.

It should cover at least:

1. load context length
2. prompt truncation / prompt-size cap
3. requested output cap
4. partial-completion behavior
5. whether the run is Huawei-conservative
6. diagnostic correlation metadata for log matching

The goal is not to expose every llama.cpp knob to Flutter. The goal is to stop relying on implicit defaults that the app cannot inspect.

### 5.2 Thread the policy through the full call chain

The policy must travel through:

1. `LlmInferenceRequest`
2. `LocalLlmEngine.generate()`
3. `LlmRuntimeBridge.generateText()`
4. `LlmRuntimePlugin.generateText`
5. `LocalLlmRuntime.generateText()`
6. `GgufLlamaCppBackend.generate()`

Even if the wrapped AAR only exposes a narrow API, the app should still explicitly log and enforce the parts it owns, especially prompt bounds and policy selection.

### 5.3 Separate readiness policy from generation policy, but keep them linked

The current code proves only that the load path uses `contextLength = 1024`.

The new design should make this relationship explicit:

1. readiness/load and generation may use different operations,
2. but they must be created from the same **Huawei conservative policy family**, not scattered literals,
3. and logs must show which policy was chosen for each request.

### 5.4 Add native-variant observability before forcing fallback

The app should log:

1. manufacturer / model / sdk
2. selected conservative policy id
3. prompt length before generation
4. whether a cached session was reused
5. whether the run is the first real generation after load

If the wrapped native layer exposes selected backend details, include them. If it does not, the app should at least log enough context to correlate a tombstone with the app-owned request.

### 5.5 Preserve a controlled conservative variant fallback

If explicit generation-policy control still aborts on Huawei, the next safe step is **not** to disable local LLM. The next safe step is to move Huawei onto a more conservative packaged native path.

This fallback should stay explicit and limited:

1. Huawei-only or model-family-specific if necessary;
2. implemented as a controlled build/runtime choice;
3. backed by regression tests and device verification notes.

---

## 6. Component-Level Changes

### 6.1 Dart request and bridge contract

Files in scope:

1. `lib/features/ai_chat/domain/llm_engine.dart`
2. `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`
3. `lib/features/ai_chat/infrastructure/local_llm_engine.dart`

Responsibilities:

1. extend the local-generation request contract with explicit generation-policy fields;
2. serialize those fields over the method channel;
3. keep non-local backends untouched.

### 6.2 Kotlin runtime policy ownership

Files in scope:

1. `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`
2. `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt`
3. `android/app/src/main/kotlin/com/example/note_secret_search/GgufLlamaCppBackend.kt`

Responsibilities:

1. construct the conservative generation policy;
2. apply prompt/output bounds before native predict;
3. log request-scoped diagnostic metadata;
4. keep load and generate configuration derived from the same policy object.

### 6.3 Native variant fallback boundary

Files in scope:

1. `android/app/build.gradle.kts`
2. `android/app/src/main/kotlin/com/example/note_secret_search/LlmBackendFactory.kt`
3. any future repo-owned wrapper or packaging note required for AAR selection

Responsibilities:

1. preserve the current Huawei-safe AAR as the default baseline;
2. make it possible to introduce a more conservative Huawei-targeted variant path without rewriting unrelated runtime code;
3. keep the fallback design separate from the primary parameter-contract fix.

---

## 7. Data Flow After the Fix

The intended local generation flow becomes:

1. `AiChatOrchestrator` resolves a ready local backend.
2. `LlmInferenceRequest` includes an explicit local generation policy payload.
3. `LocalLlmEngine.generate()` forwards both prompt and policy.
4. `MethodChannelLlmRuntimeBridge.generateText()` passes policy fields to Android.
5. `LocalLlmRuntime.generateText()` derives a concrete Huawei-safe generation configuration and logs it.
6. `GgufLlamaCppBackend.generate()` applies prompt/output bounds and calls the wrapped helper with the app-selected conservative mode.
7. If generation succeeds, the first free-chat response returns normally.
8. If generation still aborts, logs and tombstone correlation determine whether to escalate to conservative native-variant fallback.

---

## 8. Testing Strategy

### 8.1 Dart tests

Add or extend tests to prove:

1. local generation requests serialize policy fields over the bridge;
2. existing local-chat orchestration still routes to the local backend when readiness is true;
3. no external-provider behavior regresses.

### 8.2 Kotlin tests

Add or extend tests to prove:

1. Huawei policy selects the conservative context/prompt/output configuration;
2. `GgufLlamaCppBackend.generate()` uses that policy instead of ad hoc literals;
3. generated diagnostic metadata remains consistent for reused vs newly loaded sessions.

### 8.3 Device verification

The success criteria are:

1. `/ai/chat` free-chat on Huawei `SPN_AL00` no longer aborts on the first local reply;
2. the reply is produced by the local backend, not by external fallback;
3. if fallback to a more conservative native variant is required, the device still produces a local response and the route is documented.

---

## 9. Risks and Boundaries

1. The wrapped AAR may expose fewer knobs than the app ultimately wants.
2. The primary fix may improve observability without fully solving the crash.
3. If the crash is variant-specific, the repo may need a second-stage AAR packaging change.
4. The design intentionally avoids broad backend replacement, external provider changes, or unrelated chat refactors.

---

## 10. Final Direction

The correct next move is:

> **First make the generation path explicit, conservative, and observable inside our own code. Then, only if Huawei still aborts, move the device onto a more conservative native variant while keeping local generation enabled.**

That sequence preserves the user’s success criterion, fits the current repo structure, and addresses the strongest evidence we have today.
