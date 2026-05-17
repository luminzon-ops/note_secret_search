# Local LLM First Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first complete local LLM product slice for Android: runtime readiness in model management, a formal `/ai/chat` page with private QA and free chat, and SQLCipher-backed multi-session persistence.

**Architecture:** Reuse the existing embedding/runtime/model-management patterns instead of inventing a parallel stack. Add a dedicated `ai_chat` feature for LLM bridge, chat orchestration, and chat persistence; keep embedding search as the context retrieval engine for private QA and optional private-context chat; keep session storage separate from runtime orchestration so A/B/C stay independently testable.

**Tech Stack:** Flutter, Riverpod, GoRouter, Kotlin MethodChannel, Android local LLM runtime backend, sqflite_sqlcipher, Flutter widget/unit tests.

---

## Preconditions / Assumptions

1. The product direction is locked by `本地LLM首批开发设计方案.md`.
2. Existing embedding runtime and model download flows remain the reference implementation for readiness/deployment behavior.
3. This plan assumes the Android local LLM backend will match the distributed LLM model format. If backend/library selection is still unresolved at implementation time, pause after Task 2 and lock that dependency before coding further.

---

## File Structure / Responsibilities

### Existing files to modify

- `android/app/src/main/kotlin/com/example/note_secret_search/MainActivity.kt`
  - Attach/register the new LLM runtime plugin alongside the existing native security and embedding runtime plugins.

- `lib/app/router/app_router.dart`
  - Add the formal `/ai/chat` route branch and wire the AI chat page into the app shell.

- `lib/shared/widgets/app_shell.dart`
  - Add the AI chat navigation destination.

- `lib/core/storage/database/database_schema.dart`
  - Add chat session/message tables required for C.

- `lib/features/ai_models/application/model_download_providers.dart`
  - Trigger LLM runtime verification after LLM model downloads complete.

- `lib/features/ai_models/application/model_selection_providers.dart`
  - Add active local LLM selection, readiness, and self-healing persistence logic.

- `lib/features/ai_models/presentation/model_management_page.dart`
  - Display LLM runtime state, active local LLM marker, and activation controls.

- `lib/features/ai_models/presentation/model_presentation_formatter.dart`
  - Add LLM-aware deployment labels so embedding and LLM deployment copy stays aligned.

### New Flutter files to create

- `lib/features/ai_chat/domain/llm_runtime_status.dart`
  - LLM runtime status enum + runtime state model.

- `lib/features/ai_chat/domain/llm_engine.dart`
  - Request/response/value objects + `LlmEngine` interface.

- `lib/features/ai_chat/domain/chat_message.dart`
  - UI/domain message model shared by orchestration and persistence.

- `lib/features/ai_chat/domain/chat_session.dart`
  - Session entity for multi-session persistence.

- `lib/features/ai_chat/domain/chat_context_models.dart`
  - Request/response/context-source models for private QA and optional private-context chat.

- `lib/features/ai_chat/domain/chat_session_repository.dart`
  - Session/message persistence repository contract.

- `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`
  - MethodChannel wrapper for inspect/ensure/generate/release calls.

- `lib/features/ai_chat/infrastructure/local_llm_engine.dart`
  - Real Flutter `LlmEngine` implementation backed by the bridge.

- `lib/features/ai_chat/infrastructure/sqlite_chat_session_repository.dart`
  - SQLCipher-backed chat session/message storage implementation.

- `lib/features/ai_chat/application/llm_runtime_providers.dart`
  - Bridge, engine, runtime-state, and active-model providers for LLM.

- `lib/features/ai_chat/application/ai_chat_providers.dart`
  - Query state, tab mode, orchestration controller, and answer generation flow.

- `lib/features/ai_chat/application/chat_session_providers.dart`
  - Session repository + session list/current session/message providers.

- `lib/features/ai_chat/presentation/ai_chat_page.dart`
  - Formal `/ai/chat` page containing the shared shell and the two tabs.

- `lib/features/ai_chat/presentation/private_qa_tab.dart`
  - Private QA tab UI.

- `lib/features/ai_chat/presentation/free_chat_tab.dart`
  - Free chat tab UI + private-context controls.

- `lib/features/ai_chat/presentation/chat_message_list.dart`
  - Shared message rendering list.

- `lib/features/ai_chat/presentation/chat_input_bar.dart`
  - Shared input/composer area.

- `lib/features/ai_chat/presentation/chat_runtime_banner.dart`
  - Shared readiness/error banner with jump-to-model-management CTA.

- `lib/features/ai_chat/presentation/manual_context_picker_sheet.dart`
  - Manual secret/note selection UI used by free chat private-context mode.

### New Android files to create

- `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt`
  - MethodChannel handler for inspect/ensure/generate/release operations.

- `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`
  - Runtime facade wrapping the chosen Android local LLM backend.

- `android/app/src/main/kotlin/com/example/note_secret_search/LlmModelSessionManager.kt`
  - Single-active-model session manager for LLM sessions.

### Tests to create / modify

- `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`
  - Runtime-state mapping, generation decoding, and bridge error propagation.

- `test/features/ai_chat/application/llm_runtime_providers_test.dart`
  - Active LLM readiness and runtime-state provider behavior.

- `test/features/ai_models/application/model_download_providers_test.dart`
  - LLM download completion triggers readiness verification.

- `test/features/ai_models/application/model_selection_providers_test.dart`
  - Active LLM selection self-healing and readiness gating.

- `test/features/ai_models/presentation/model_management_page_test.dart`
  - LLM deployment state rendering + active LLM UI behavior.

- `test/features/ai_chat/application/ai_chat_providers_test.dart`
  - Private QA and free chat orchestration behavior.

- `test/features/ai_chat/application/chat_session_providers_test.dart`
  - Session/message persistence and recovery flows.

- `test/features/ai_chat/presentation/ai_chat_page_test.dart`
  - Route rendering, tab switching, degraded-state blocking, and retry/CTA behavior.

---

## Task 1: Add the LLM domain layer and Flutter runtime bridge boundary

**Files:**
- Create: `lib/features/ai_chat/domain/llm_runtime_status.dart`
- Create: `lib/features/ai_chat/domain/llm_engine.dart`
- Create: `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`
- Create: `test/features/ai_chat/infrastructure/local_llm_engine_test.dart`

- [ ] **Step 1: Write failing runtime mapping tests**

Create `test/features/ai_chat/infrastructure/local_llm_engine_test.dart` with cases that assert:

```dart
test('maps ready runtime payload into LlmRuntimeState', () async {});
test('maps degraded runtime payload into non-ready state', () async {});
test('maps generateText payload into LlmInferenceResponse', () async {});
```

The fixture payloads should mirror the planned channel contract:

```dart
const readyPayload = {
  'ready': true,
  'reason': 'Local LLM model is ready.',
  'status': 'ready',
  'modelPath': '/data/user/0/app/files/models/phi.gguf',
};

const responsePayload = {
  'text': '这是本地模型回答。',
  'finishReason': 'stop',
  'usedPrivateContext': false,
};
```

- [ ] **Step 2: Define the runtime status model**

Create `lib/features/ai_chat/domain/llm_runtime_status.dart` with a dedicated enum and state object:

```dart
enum LlmRuntimeStatus {
  notInstalled,
  missing,
  installedUnverified,
  ready,
  degraded,
}

class LlmRuntimeState {
  const LlmRuntimeState({
    required this.ready,
    required this.reason,
    required this.status,
    this.modelPath,
    this.checkedAt,
  });

  final bool ready;
  final String reason;
  final LlmRuntimeStatus status;
  final String? modelPath;
  final DateTime? checkedAt;
}
```

- [ ] **Step 3: Define the `LlmEngine` contract and request/response models**

Create `lib/features/ai_chat/domain/llm_engine.dart` with:

```dart
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';

class LlmInferenceRequest {
  const LlmInferenceRequest({
    required this.model,
    required this.prompt,
    required this.usedPrivateContext,
  });

  final ModelRegistryEntry model;
  final String prompt;
  final bool usedPrivateContext;
}

class LlmInferenceResponse {
  const LlmInferenceResponse({
    required this.text,
    required this.finishReason,
    required this.usedPrivateContext,
  });

  final String text;
  final String finishReason;
  final bool usedPrivateContext;
}

abstract interface class LlmEngine {
  Future<LlmRuntimeState> getState(ModelRegistryEntry model);
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request);
  Future<void> releaseModel(String modelId);
}
```

- [ ] **Step 4: Create the MethodChannel bridge skeleton**

Create `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart` with a single `MethodChannel` contract:

```dart
import 'package:flutter/services.dart';

abstract interface class LlmRuntimeBridge {
  Future<Map<String, dynamic>> inspectModel({required String modelId, required String modelPath});
  Future<Map<String, dynamic>> ensureModelReady({required String modelId, required String modelPath});
  Future<Map<String, dynamic>> generateText({
    required String modelId,
    required String modelPath,
    required String prompt,
    required bool usedPrivateContext,
  });
  Future<void> releaseModel({required String modelId});
}

class MethodChannelLlmRuntimeBridge implements LlmRuntimeBridge {
  static const _channel = MethodChannel('note_secret_search/llm_runtime');
  // implement with invokeMapMethod / invokeMethod
}
```

- [ ] **Step 5: Run the targeted tests**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart
```

Expected: FAIL before the engine implementation exists, then PASS after the bridge-facing mapping code is added in Task 3.

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_chat/domain/llm_runtime_status.dart lib/features/ai_chat/domain/llm_engine.dart lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart test/features/ai_chat/infrastructure/local_llm_engine_test.dart
git commit -m "feat: add local llm runtime bridge contracts"
```

---

## Task 2: Implement the Android LLM runtime plugin and session manager

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/note_secret_search/MainActivity.kt`
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt`
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt`
- Create: `android/app/src/main/kotlin/com/example/note_secret_search/LlmModelSessionManager.kt`

- [ ] **Step 1: Define the channel contract in a test note inside the plan branch**

Use the following Android channel contract and keep it identical to the Flutter bridge:

```text
Channel: note_secret_search/llm_runtime
Methods:
- inspectModel
- ensureModelReady
- generateText
- releaseModel
```

- [ ] **Step 2: Add the session manager**

Create `LlmModelSessionManager.kt` using the same single-active-model policy as the embedding runtime:

```kotlin
package com.example.note_secret_search

class LlmModelSessionManager<T> {
    private var activeModelId: String? = null
    private var activeSession: T? = null

    fun get(modelId: String): T? = if (activeModelId == modelId) activeSession else null

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
}
```

- [ ] **Step 3: Implement `LocalLlmRuntime.kt` as the backend facade**

Create a facade with the same responsibilities as `OnnxEmbeddingRuntime`, but for text generation:

```kotlin
package com.example.note_secret_search

import android.content.Context
import java.io.File

class LocalLlmRuntime(
    private val context: Context,
    private val sessionManager: LlmModelSessionManager<Any>,
) {
    fun inspectModel(modelId: String, modelPath: String): Map<String, Any?> { /* file + metadata validation */ }
    fun ensureModelReady(modelId: String, modelPath: String): Map<String, Any?> { /* minimal generation probe */ }
    fun generateText(
        modelId: String,
        modelPath: String,
        prompt: String,
        usedPrivateContext: Boolean,
    ): Map<String, Any?> { /* call chosen backend */ }
    fun releaseModel(modelId: String) { /* dispose cached session */ }
}
```

The returned map keys must include:

```text
ready, reason, status, modelPath, text, finishReason, usedPrivateContext
```

- [ ] **Step 4: Implement `LlmRuntimePlugin.kt`**

Mirror the style of `EmbeddingRuntimePlugin.kt`:

```kotlin
class LlmRuntimePlugin(
    context: Context,
) : MethodChannel.MethodCallHandler {
    private val runtime = LocalLlmRuntime(
        context = context,
        sessionManager = LlmModelSessionManager(),
    )
    // attachToEngine + onMethodCall with inspect/ensure/generate/release
}
```

Use the same error categories already used elsewhere:

```text
INVALID_ARGUMENT
RUNTIME_NOT_READY
LLM_RUNTIME_ERROR
```

- [ ] **Step 5: Register the plugin in `MainActivity.kt`**

Extend the existing `MainActivity` shape to hold and attach the LLM plugin:

```kotlin
private lateinit var llmRuntimePlugin: LlmRuntimePlugin

override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    nativeSecurityPlugin = NativeSecurityPlugin(this, recentTaskShieldView)
    nativeSecurityPlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)

    embeddingRuntimePlugin = EmbeddingRuntimePlugin(this)
    embeddingRuntimePlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)

    llmRuntimePlugin = LlmRuntimePlugin(this)
    llmRuntimePlugin.attachToEngine(flutterEngine.dartExecutor.binaryMessenger)
}
```

- [ ] **Step 6: Run static verification**

Run:

```powershell
flutter analyze
```

Expected: no new Dart analyzer issues; note any Kotlin-only backend compilation issues separately if the chosen LLM runtime backend requires extra Gradle wiring.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/kotlin/com/example/note_secret_search/MainActivity.kt android/app/src/main/kotlin/com/example/note_secret_search/LlmRuntimePlugin.kt android/app/src/main/kotlin/com/example/note_secret_search/LocalLlmRuntime.kt android/app/src/main/kotlin/com/example/note_secret_search/LlmModelSessionManager.kt
git commit -m "feat: add android local llm runtime plugin"
```

---

## Task 3: Implement the Flutter LLM engine and runtime providers

**Files:**
- Create: `lib/features/ai_chat/infrastructure/local_llm_engine.dart`
- Create: `lib/features/ai_chat/application/llm_runtime_providers.dart`
- Create: `test/features/ai_chat/application/llm_runtime_providers_test.dart`

- [ ] **Step 1: Write the provider tests first**

Create `test/features/ai_chat/application/llm_runtime_providers_test.dart` with cases for:

```dart
test('activeLocalLlmModelProvider returns only ready llm models', () async {});
test('localLlmReadinessProvider reports missing active model', () async {});
test('llmRuntimeStatesProvider surfaces degraded runtime state', () async {});
```

- [ ] **Step 2: Implement `LocalLlmEngine`**

Create `lib/features/ai_chat/infrastructure/local_llm_engine.dart`:

```dart
class LocalLlmEngine implements LlmEngine {
  LocalLlmEngine({required LlmRuntimeBridge bridge}) : _bridge = bridge;

  final LlmRuntimeBridge _bridge;

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) async { /* inspect/ensure mapping */ }

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async { /* generateText mapping */ }

  @override
  Future<void> releaseModel(String modelId) => _bridge.releaseModel(modelId: modelId);
}
```

- [ ] **Step 3: Wire the provider graph**

Create `lib/features/ai_chat/application/llm_runtime_providers.dart` with:

```dart
final llmRuntimeBridgeProvider = Provider<LlmRuntimeBridge>((ref) {
  return MethodChannelLlmRuntimeBridge();
});

final llmEngineProvider = Provider<LlmEngine>((ref) {
  return LocalLlmEngine(bridge: ref.watch(llmRuntimeBridgeProvider));
});

final llmRuntimeStatesProvider = FutureProvider<Map<String, LlmRuntimeState>>((ref) async {
  // iterate installed models of type == 'llm'
});
```

Keep the provider style aligned with `embedding_runtime_providers.dart` and `model_selection_providers.dart`.

- [ ] **Step 4: Run the new tests**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_chat/infrastructure/local_llm_engine.dart lib/features/ai_chat/application/llm_runtime_providers.dart test/features/ai_chat/infrastructure/local_llm_engine_test.dart test/features/ai_chat/application/llm_runtime_providers_test.dart
git commit -m "feat: wire flutter local llm runtime providers"
```

---

## Task 4: Extend model download, selection, and model-management UI for LLM readiness

**Files:**
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
- Modify: `lib/features/ai_models/application/model_selection_providers.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`
- Modify: `test/features/ai_models/application/model_selection_providers_test.dart`
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Write failing tests for LLM readiness and selection**

Add tests asserting:

```dart
test('download completion verifies llm runtime for llm models', () async {});
test('active local llm selection self-heals when runtime degrades', () async {});
testWidgets('model management page shows 当前本地LLM for ready llm model', (tester) async {});
```

- [ ] **Step 2: Extend download completion verification**

In `model_download_providers.dart`, branch on `entry.type`:

```dart
if (entry.type == 'embedding') {
  await embeddingEngine.getState(savedEntry);
}
if (entry.type == 'llm') {
  await llmEngine.getState(savedEntry);
}
```

Then invalidate both runtime-state providers after saving the registry entry.

- [ ] **Step 3: Add active local LLM selection and readiness**

In `model_selection_providers.dart`, add:

```dart
const _activeLlmModelIdKey = 'ai.active_llm_model_id';

final activeLocalLlmModelProvider = FutureProvider<ModelRegistryEntry?>((ref) async { /* ready llm only */ });
final localLlmReadinessProvider = FutureProvider<LocalLlmReadiness>((ref) async { /* reason + runtime state */ });
```

Mirror the active embedding self-healing rules: if the stored model is missing, not installed, or runtime-degraded, clear the preference.

- [ ] **Step 4: Expand model-management UI**

Update `model_management_page.dart` so it:

1. Reads both embedding and LLM runtime states.
2. Shows LLM deployment status in installed-model cards.
3. Marks the active LLM with trailing text:

```text
当前本地LLM
```

4. Disables activation when the runtime state is not ready.

- [ ] **Step 5: Align formatter copy**

Update `model_presentation_formatter.dart` so LLM statuses have copy parallel to embedding, for example:

```text
部署状态：本地已就绪，可用于本地问答。
部署状态：本地已安装，但运行时尚未校验。
部署状态：运行时异常，当前不可直接使用。
```

- [ ] **Step 6: Run verification**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
flutter test test/features/ai_models/application/model_selection_providers_test.dart
flutter test test/features/ai_models/presentation/model_management_page_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/ai_models/application/model_download_providers.dart lib/features/ai_models/application/model_selection_providers.dart lib/features/ai_models/presentation/model_management_page.dart lib/features/ai_models/presentation/model_presentation_formatter.dart test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/application/model_selection_providers_test.dart test/features/ai_models/presentation/model_management_page_test.dart
git commit -m "feat: expose local llm readiness in model management"
```

---

## Task 5: Add the AI chat route, shell navigation, and page scaffold

**Files:**
- Modify: `lib/app/router/app_router.dart`
- Modify: `lib/shared/widgets/app_shell.dart`
- Create: `lib/features/ai_chat/presentation/ai_chat_page.dart`
- Create: `lib/features/ai_chat/presentation/chat_message_list.dart`
- Create: `lib/features/ai_chat/presentation/chat_input_bar.dart`
- Create: `lib/features/ai_chat/presentation/chat_runtime_banner.dart`
- Create: `test/features/ai_chat/presentation/ai_chat_page_test.dart`

- [ ] **Step 1: Write the widget tests first**

Add tests asserting:

```dart
testWidgets('app shell shows AI navigation destination', (tester) async {});
testWidgets('AI chat page renders 私密内容问答 and 自由聊天 tabs', (tester) async {});
testWidgets('AI chat page shows jump-to-model-management CTA when llm is unavailable', (tester) async {});
```

- [ ] **Step 2: Add the route and navigation destination**

Modify `app_router.dart` and `app_shell.dart` so the shell includes a new branch:

```dart
StatefulShellBranch(routes: [
  GoRoute(
    path: '/ai/chat',
    name: 'aiChat',
    builder: (context, state) => const AiChatPage(),
  ),
]),
```

And add a matching `NavigationDestination` label:

```dart
NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: '问答')
```

- [ ] **Step 3: Build the shared page scaffold**

Create `AiChatPage` with:

1. Shared top runtime banner.
2. `DefaultTabController(length: 2)`.
3. Message area placeholder.
4. Shared input bar placeholder.

The two visible tab labels must be exactly:

```text
私密内容问答
自由聊天
```

- [ ] **Step 4: Run widget verification**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/router/app_router.dart lib/shared/widgets/app_shell.dart lib/features/ai_chat/presentation/ai_chat_page.dart lib/features/ai_chat/presentation/chat_message_list.dart lib/features/ai_chat/presentation/chat_input_bar.dart lib/features/ai_chat/presentation/chat_runtime_banner.dart test/features/ai_chat/presentation/ai_chat_page_test.dart
git commit -m "feat: add ai chat page scaffold"
```

---

## Task 6: Implement private QA and free-chat orchestration

**Files:**
- Create: `lib/features/ai_chat/domain/chat_context_models.dart`
- Create: `lib/features/ai_chat/domain/chat_message.dart`
- Create: `lib/features/ai_chat/application/ai_chat_providers.dart`
- Create: `lib/features/ai_chat/presentation/private_qa_tab.dart`
- Create: `lib/features/ai_chat/presentation/free_chat_tab.dart`
- Create: `test/features/ai_chat/application/ai_chat_providers_test.dart`

- [ ] **Step 1: Write orchestration tests first**

Add tests for:

```dart
test('private QA blocks when llm readiness is false', () async {});
test('private QA uses semantic retrieval before local llm generation', () async {});
test('free chat can answer without private context when llm is ready', () async {});
test('free chat with allowPrivateContext=true can combine auto retrieval and manual items', () async {});
```

- [ ] **Step 2: Define the chat request/response models**

Create context-source models that encode the agreed behavior:

```dart
enum ChatMode { privateQa, freeChat }
enum ChatContextSource { none, autoRetrieved, manuallySelected, mixed }

class AiChatRequest { /* mode, userInput, allowPrivateContext, manualItems */ }
class AiChatResponse { /* text, contextSummary, usedPrivateContext, sourceType */ }
```

- [ ] **Step 3: Implement the orchestration controller**

In `ai_chat_providers.dart`, create a controller that:

1. For `privateQa`:
   - requires LLM readiness;
   - requires semantic readiness;
   - retrieves top-k context;
   - builds the final prompt;
   - calls `llmEngine.generate`.
2. For `freeChat`:
   - requires only LLM readiness by default;
   - optionally retrieves context when `allowPrivateContext == true`;
   - merges manual items with auto-retrieved context.

- [ ] **Step 4: Render the two tabs against the controller**

`PrivateQaTab` should show:

```text
本次回答基于本地私密内容生成
```

after successful answers using private context.

`FreeChatTab` should expose:

```text
允许参考私密内容
```

as a toggle.

- [ ] **Step 5: Run targeted tests**

Run:

```powershell
flutter test test/features/ai_chat/application/ai_chat_providers_test.dart
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_chat/domain/chat_context_models.dart lib/features/ai_chat/domain/chat_message.dart lib/features/ai_chat/application/ai_chat_providers.dart lib/features/ai_chat/presentation/private_qa_tab.dart lib/features/ai_chat/presentation/free_chat_tab.dart test/features/ai_chat/application/ai_chat_providers_test.dart test/features/ai_chat/presentation/ai_chat_page_test.dart
git commit -m "feat: add private qa and free chat orchestration"
```

---

## Task 7: Add the manual private-context picker and degraded-state UX

**Files:**
- Create: `lib/features/ai_chat/presentation/manual_context_picker_sheet.dart`
- Modify: `lib/features/ai_chat/presentation/free_chat_tab.dart`
- Modify: `lib/features/ai_chat/presentation/ai_chat_page.dart`
- Modify: `test/features/ai_chat/presentation/ai_chat_page_test.dart`

- [ ] **Step 1: Add failing widget tests**

Add tests asserting:

```dart
testWidgets('free chat shows manual context entry point when private context is enabled', (tester) async {});
testWidgets('manual picker remains usable when semantic readiness is false but llm is ready', (tester) async {});
testWidgets('private QA send action is disabled when semantic readiness is false', (tester) async {});
```

- [ ] **Step 2: Build the manual picker sheet**

Create `manual_context_picker_sheet.dart` as a bottom sheet that can list selectable notes/secrets and returns selected item ids.

The first version can be simple:

```dart
class ManualContextPickerSheet extends ConsumerWidget {
  const ManualContextPickerSheet({required this.initialIds, super.key});
  final Set<String> initialIds;
}
```

No search, no deep links, no advanced filtering.

- [ ] **Step 3: Apply degraded UX rules**

Ensure the UI behavior matches the agreed design:

1. Private QA send is blocked when semantic readiness is false.
2. Free chat pure mode works when LLM is ready.
3. Free chat manual context remains available even if automatic semantic retrieval is unavailable.
4. Runtime banners include CTA to `/models` where appropriate.

- [ ] **Step 4: Run widget tests**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_chat/presentation/manual_context_picker_sheet.dart lib/features/ai_chat/presentation/free_chat_tab.dart lib/features/ai_chat/presentation/ai_chat_page.dart test/features/ai_chat/presentation/ai_chat_page_test.dart
git commit -m "feat: add manual private context selection for chat"
```

---

## Task 8: Add chat session persistence schema and repository implementation

**Files:**
- Modify: `lib/core/storage/database/database_schema.dart`
- Create: `lib/features/ai_chat/domain/chat_session.dart`
- Create: `lib/features/ai_chat/domain/chat_session_repository.dart`
- Create: `lib/features/ai_chat/infrastructure/sqlite_chat_session_repository.dart`
- Create: `test/features/ai_chat/application/chat_session_providers_test.dart`

- [ ] **Step 1: Write repository tests first**

Add tests for:

```dart
test('creates a chat session and stores messages', () async {});
test('lists sessions ordered by updatedAt desc', () async {});
test('loads messages for an existing session', () async {});
```

- [ ] **Step 2: Extend the SQLCipher schema**

Add two new tables to `database_schema.dart`:

```sql
CREATE TABLE IF NOT EXISTS chat_sessions (
  id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  title TEXT NOT NULL,
  allow_private_context INTEGER NOT NULL DEFAULT 0,
  last_model_id TEXT,
  archived INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)

CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  status TEXT NOT NULL,
  used_private_context INTEGER NOT NULL DEFAULT 0,
  auto_retrieved_context_summary TEXT,
  manual_context_item_ids_json TEXT,
  related_source_ids_json TEXT,
  created_at INTEGER NOT NULL
)
```

- [ ] **Step 3: Define the session/message entities and repository**

Create `chat_session.dart` with `ChatSession`, `ChatStoredMessage`, `ChatMessageRole`, and `ChatMessageStatus`.

Create `chat_session_repository.dart` with methods:

```dart
Future<void> saveSession(ChatSession session);
Future<void> saveMessage(ChatStoredMessage message);
Future<List<ChatSession>> listSessions();
Future<List<ChatStoredMessage>> listMessages(String sessionId);
Future<ChatSession?> getSession(String sessionId);
```

- [ ] **Step 4: Implement the SQLite repository**

Create `sqlite_chat_session_repository.dart` using `AppDatabase` and JSON-encoded arrays for `manual_context_item_ids_json` and `related_source_ids_json`.

- [ ] **Step 5: Run persistence tests**

Run:

```powershell
flutter test test/features/ai_chat/application/chat_session_providers_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/storage/database/database_schema.dart lib/features/ai_chat/domain/chat_session.dart lib/features/ai_chat/domain/chat_session_repository.dart lib/features/ai_chat/infrastructure/sqlite_chat_session_repository.dart test/features/ai_chat/application/chat_session_providers_test.dart
git commit -m "feat: add chat session persistence"
```

---

## Task 9: Wire session providers, recovery, and multi-session UI into the chat page

**Files:**
- Create: `lib/features/ai_chat/application/chat_session_providers.dart`
- Modify: `lib/features/ai_chat/application/ai_chat_providers.dart`
- Modify: `lib/features/ai_chat/presentation/ai_chat_page.dart`
- Modify: `lib/features/ai_chat/presentation/chat_message_list.dart`
- Modify: `test/features/ai_chat/application/chat_session_providers_test.dart`
- Modify: `test/features/ai_chat/presentation/ai_chat_page_test.dart`

- [ ] **Step 1: Add failing tests for recovery and switching**

Add tests asserting:

```dart
test('restores the most recent chat session on page load', () async {});
test('switching sessions loads the correct message history', () async {});
testWidgets('AI chat page lists existing sessions and can switch between them', (tester) async {});
```

- [ ] **Step 2: Add session providers**

Create providers for:

```dart
final chatSessionRepositoryProvider = Provider<ChatSessionRepository>((ref) { ... });
final chatSessionsProvider = FutureProvider<List<ChatSession>>((ref) async { ... });
final currentChatSessionIdProvider = StateProvider<String?>((ref) => null);
final currentChatMessagesProvider = FutureProvider<List<ChatStoredMessage>>((ref) async { ... });
```

- [ ] **Step 3: Persist new messages from the orchestration layer**

Update `ai_chat_providers.dart` so each successful user send writes:

1. User message.
2. Assistant message.
3. Session metadata update.

When generation fails, persist the assistant-side failed message with `status == failed`.

- [ ] **Step 4: Add a minimal session list UI**

Update `AiChatPage` to show a compact session list area or drawer entry with:

```text
最近会话
```

Each item should show title + updated time. Keep it simple; no archive/delete UI yet.

- [ ] **Step 5: Run verification**

Run:

```powershell
flutter test test/features/ai_chat/application/chat_session_providers_test.dart
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_chat/application/chat_session_providers.dart lib/features/ai_chat/application/ai_chat_providers.dart lib/features/ai_chat/presentation/ai_chat_page.dart lib/features/ai_chat/presentation/chat_message_list.dart test/features/ai_chat/application/chat_session_providers_test.dart test/features/ai_chat/presentation/ai_chat_page_test.dart
git commit -m "feat: add multi-session chat recovery"
```

---

## Task 10: Full verification, copy review, and implementation handoff

**Files:**
- Review: `本地LLM首批开发设计方案.md`
- Review: `docs/superpowers/plans/2026-04-25-local-llm-first-batch.md`
- Review: all files changed by Tasks 1-9

- [ ] **Step 1: Run the focused test suite**

Run:

```powershell
flutter test test/features/ai_chat/infrastructure/local_llm_engine_test.dart
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart
flutter test test/features/ai_chat/application/ai_chat_providers_test.dart
flutter test test/features/ai_chat/application/chat_session_providers_test.dart
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart
flutter test test/features/ai_models/application/model_download_providers_test.dart
flutter test test/features/ai_models/application/model_selection_providers_test.dart
flutter test test/features/ai_models/presentation/model_management_page_test.dart
flutter analyze
```

Expected: all tests PASS; analyzer clean.

- [ ] **Step 2: Verify spec coverage manually**

Check each requirement from `本地LLM首批开发设计方案.md` against completed work:

1. A: LLM runtime + model management readiness.
2. B: `/ai/chat` + dual tabs + private QA + free chat + optional private context.
3. C: session persistence + recovery + multi-session switching.

If any item is missing, add a follow-up task before declaring the implementation complete.

- [ ] **Step 3: Prepare merge/handoff summary**

Write a short implementation summary that lists:

```text
- Active local LLM runtime status support
- AI chat page behavior
- Session persistence behavior
- Known follow-up items intentionally deferred
```

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat: complete first local llm product slice"
```

---

## Self-Review

### Spec coverage

- A subsystem coverage: Tasks 1-4.
- B subsystem coverage: Tasks 5-7.
- C subsystem coverage: Tasks 8-9.
- Verification and handoff: Task 10.

### Placeholder scan

- The only intentional open dependency is the exact Android local LLM backend library/model-format pair. That is called out explicitly in Preconditions so implementation does not guess silently.

### Type consistency

- `LlmRuntimeStatus`, `LlmRuntimeState`, `LlmInferenceRequest`, `LlmInferenceResponse`, `ChatMode`, `ChatContextSource`, `ChatSession`, and `ChatStoredMessage` are used consistently across the plan.
