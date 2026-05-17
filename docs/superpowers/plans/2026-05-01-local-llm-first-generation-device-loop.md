# Local LLM First Generation Device Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the minimum local-LLM catalog and activation prerequisites so an installed runtime-ready local LLM can be selected in model management and used by the existing `/ai/chat` local-first flow.

**Architecture:** Reuse the current asset-backed catalog, existing LLM runtime verification after download, and the embedding-selection controller pattern. Keep the LLM read-side readiness logic where it already lives in `llm_runtime_providers.dart`, add only the missing write-side selection path there, and surface one gated activation control in `model_management_page.dart`.

**Tech Stack:** Flutter, Dart, Riverpod, SharedPreferences, existing AI model download/runtime providers, Flutter unit/widget tests, Flutter analyze.

---

## File Structure / Responsibilities

### Existing files to modify

- `assets/model_catalog/built_in_catalog.json`
  - Add one built-in `type: "llm"` catalog entry that can flow through the existing download/runtime verification pipeline.

- `lib/features/ai_chat/application/llm_runtime_providers.dart`
  - Add the missing active-local-LLM controller/provider write path around `_activeLlmModelIdKey` while preserving existing read-side self-healing behavior.

- `lib/features/ai_models/presentation/model_management_page.dart`
  - Add the local-LLM activation CTA in the catalog entry actions and gate it to installed + runtime-ready LLM entries.

- `test/features/ai_chat/application/llm_runtime_providers_test.dart`
  - Add test-first coverage for setting/clearing the active local LLM selection and ensuring readiness updates correctly.

- `test/features/ai_models/presentation/model_management_page_test.dart`
  - Add test-first coverage for the new local-LLM activation CTA and disabled-state gating.

### Existing files to validate but not structurally change

- `lib/features/ai_models/application/model_download_providers.dart`
  - Verify the existing `type == 'llm'` post-download readiness path remains sufficient.

- `lib/features/ai_chat/application/ai_chat_providers.dart`
  - Validate that the existing local-first backend resolution works once readiness becomes true.

- `test/features/ai_chat/presentation/ai_chat_page_test.dart`
  - Keep existing local-chat readiness behavior passing.

---

## Task 1: Add failing provider tests for explicit active local LLM selection

**Files:**
- Modify: `test/features/ai_chat/application/llm_runtime_providers_test.dart`
- Modify: `lib/features/ai_chat/application/llm_runtime_providers.dart`

- [ ] **Step 1: Write the failing test for setting an active local LLM**

Add this test to `test/features/ai_chat/application/llm_runtime_providers_test.dart`:

```dart
test('active local llm controller persists selected model id', () async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
      modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
      llmRuntimeStatesProvider.overrideWith(
        (ref) async => {
          'llm-1': const LlmRuntimeState(
            ready: true,
            reason: 'ready',
            status: LlmRuntimeStatus.ready,
          ),
        },
      ),
    ],
  );

  addTearDown(container.dispose);

  await container.read(activeLocalLlmSelectionControllerProvider).setActiveLocalLlmModel('llm-1');

  final preferences = await container.read(sharedPreferencesProvider.future);
  final selected = await container.read(activeLocalLlmModelProvider.future);

  expect(preferences.getString('ai.active_llm_model_id'), 'llm-1');
  expect(selected?.id, 'llm-1');
});
```

- [ ] **Step 2: Run the targeted test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart --plain-name "active local llm controller persists selected model id"
```

Expected:

- The test fails because `activeLocalLlmSelectionControllerProvider` or `setActiveLocalLlmModel` does not exist yet.

- [ ] **Step 3: Write the failing test for clearing the active local LLM**

Add this test to the same file:

```dart
test('active local llm controller clears selected model id', () async {
  SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
      modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
      llmRuntimeStatesProvider.overrideWith(
        (ref) async => {
          'llm-1': const LlmRuntimeState(
            ready: true,
            reason: 'ready',
            status: LlmRuntimeStatus.ready,
          ),
        },
      ),
    ],
  );

  addTearDown(container.dispose);

  await container.read(activeLocalLlmSelectionControllerProvider).setActiveLocalLlmModel(null);

  final preferences = await container.read(sharedPreferencesProvider.future);
  final selected = await container.read(activeLocalLlmModelProvider.future);

  expect(preferences.getString('ai.active_llm_model_id'), isNull);
  expect(selected, isNull);
});
```

- [ ] **Step 4: Run the targeted test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart --plain-name "active local llm controller clears selected model id"
```

Expected:

- The test fails because the controller path is still missing.

- [ ] **Step 5: Implement the minimal controller in `llm_runtime_providers.dart`**

Add the provider and controller to `lib/features/ai_chat/application/llm_runtime_providers.dart`:

```dart
final activeLocalLlmSelectionControllerProvider = Provider<ActiveLocalLlmSelectionController>((ref) {
  return ActiveLocalLlmSelectionController(ref: ref);
});

class ActiveLocalLlmSelectionController {
  ActiveLocalLlmSelectionController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> setActiveLocalLlmModel(String? modelId) async {
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    if (modelId == null || modelId.isEmpty) {
      await preferences.remove(_activeLlmModelIdKey);
    } else {
      await preferences.setString(_activeLlmModelIdKey, modelId);
    }

    _ref.invalidate(activeLocalLlmModelProvider);
    _ref.invalidate(localLlmReadinessProvider);
  }
}
```

- [ ] **Step 6: Run the provider test file to verify green**

Run:

```powershell
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart
```

Expected:

- All tests in `llm_runtime_providers_test.dart` pass.

- [ ] **Step 7: Commit**

```bash
git add test/features/ai_chat/application/llm_runtime_providers_test.dart lib/features/ai_chat/application/llm_runtime_providers.dart
git commit -m "feat: add active local llm selection controller"
```

---

## Task 2: Add failing widget tests for local LLM activation in model management

**Files:**
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`

- [ ] **Step 1: Add a recording local-LLM selection controller fake to the widget test file**

Add this helper near the other test fakes in `test/features/ai_models/presentation/model_management_page_test.dart`:

```dart
class _RecordingActiveLocalLlmSelectionController implements ActiveLocalLlmSelectionController {
  _RecordingActiveLocalLlmSelectionController();

  String? selectedModelId;

  @override
  Future<void> setActiveLocalLlmModel(String? modelId) async {
    selectedModelId = modelId;
  }
}
```

If direct interface implementation is not possible because the production controller is a class instead of an abstract interface, convert the production type to a small interface + concrete implementation while keeping behavior unchanged.

- [ ] **Step 2: Write the failing widget test for a ready installed LLM activation CTA**

Add this test to `test/features/ai_models/presentation/model_management_page_test.dart`:

```dart
testWidgets('ModelManagementPage allows activating a ready installed local llm', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final controller = _RecordingActiveLocalLlmSelectionController();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelCatalogEntriesProvider.overrideWith(
          (ref) async => const [
            ModelCatalogEntry(
              id: 'llm-1',
              type: 'llm',
              tier: 'local',
              displayName: 'Phi Local',
              description: '用于本地自由聊天。',
              sizeBytes: 104857600,
              minRamMb: 2048,
              recommendedTier: 'local',
              sources: <ModelSourceEntry>[],
            ),
          ],
        ),
        modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [
            ModelRegistryEntry(
              id: 'llm-1',
              type: 'llm',
              provider: 'builtin',
              name: 'Phi Local',
              version: '1.0.0',
              sizeBytes: 104857600,
              quantization: 'Q4_K_M',
              minRamMb: 2048,
              recommendedTier: 'local',
              localPath: '/data/models/phi.gguf',
              checksum: 'abc',
              enabled: true,
              installedAt: null,
              filePresent: true,
            ),
          ],
        ),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: true,
              reason: 'ready',
              status: LlmRuntimeStatus.ready,
            ),
          },
        ),
        embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
        activeLocalLlmSelectionControllerProvider.overrideWithValue(controller),
        modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(OutlinedButton, '设为当前本地LLM'));
  await tester.pump();

  expect(controller.selectedModelId, 'llm-1');
});
```

- [ ] **Step 3: Run the targeted widget test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage allows activating a ready installed local llm"
```

Expected:

- The test fails because the button text or activation action does not exist yet.

- [ ] **Step 4: Write the failing widget test for disabled activation when LLM runtime is degraded**

Add this test to the same file:

```dart
testWidgets('ModelManagementPage disables local llm activation when runtime is degraded', (tester) async {
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
        modelCatalogEntriesProvider.overrideWith(
          (ref) async => const [
            ModelCatalogEntry(
              id: 'llm-1',
              type: 'llm',
              tier: 'local',
              displayName: 'Phi Local',
              description: '用于本地自由聊天。',
              sizeBytes: 104857600,
              minRamMb: 2048,
              recommendedTier: 'local',
              sources: <ModelSourceEntry>[],
            ),
          ],
        ),
        modelDownloadTasksProvider.overrideWith((ref) async => const <ModelDownloadTask>[]),
        modelRegistryEntriesProvider.overrideWith(
          (ref) async => const [
            ModelRegistryEntry(
              id: 'llm-1',
              type: 'llm',
              provider: 'builtin',
              name: 'Phi Local',
              version: '1.0.0',
              sizeBytes: 104857600,
              quantization: 'Q4_K_M',
              minRamMb: 2048,
              recommendedTier: 'local',
              localPath: '/data/models/phi.gguf',
              checksum: 'abc',
              enabled: true,
              installedAt: null,
              filePresent: true,
            ),
          ],
        ),
        llmRuntimeStatesProvider.overrideWith(
          (ref) async => {
            'llm-1': const LlmRuntimeState(
              ready: false,
              reason: 'probe failed',
              status: LlmRuntimeStatus.degraded,
            ),
          },
        ),
        embeddingRuntimeStatesProvider.overrideWith((ref) async => const <String, EmbeddingEngineState>{}),
        activeModelSelectionProvider.overrideWith(
          (ref) async => const ActiveModelSelection(activeEmbeddingModelId: null),
        ),
        modelDownloadControllerProvider.overrideWith((ref) => _FakeModelDownloadController(ref: ref)),
      ],
      child: const MaterialApp(home: ModelManagementPage()),
    ),
  );

  await tester.pumpAndSettle();

  final button = tester.widget<OutlinedButton>(
    find.widgetWithText(OutlinedButton, '设为当前本地LLM'),
  );
  expect(button.onPressed, isNull);
});
```

- [ ] **Step 5: Run the targeted widget test to verify it fails for the right reason**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart --plain-name "ModelManagementPage disables local llm activation when runtime is degraded"
```

Expected:

- The test fails because the local-LLM activation button does not exist yet.

- [ ] **Step 6: Implement the minimal local-LLM activation CTA in `model_management_page.dart`**

In the catalog-entry action `Wrap`, add an LLM-specific activation button beside the existing embedding activation button:

```dart
OutlinedButton.icon(
  onPressed: !isInstalled || entry.type != 'llm' || !canActivateLlm
      ? null
      : () => ref
          .read(activeLocalLlmSelectionControllerProvider)
          .setActiveLocalLlmModel(isActiveLocalLlm ? null : entry.id),
  icon: const Icon(Icons.smart_toy_outlined),
  label: Text(isActiveLocalLlm ? '取消启用' : '设为当前本地LLM'),
),
```

Back the button with local variables derived from existing page data:

```dart
final isActiveLocalLlm = activeLlmModelId == entry.id;
final llmReady = llmRuntimeState?.ready == true;
final canActivateLlm = llmReady;
```

Keep the button LLM-only. Do not change embedding activation behavior.

- [ ] **Step 7: Run the full widget test file to verify green**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected:

- All model-management widget tests pass.

- [ ] **Step 8: Commit**

```bash
git add test/features/ai_models/presentation/model_management_page_test.dart lib/features/ai_models/presentation/model_management_page.dart
git commit -m "feat: add local llm activation controls"
```

---

## Task 3: Add the built-in local LLM catalog entry and validate the end-to-end prerequisite path

**Files:**
- Modify: `assets/model_catalog/built_in_catalog.json`
- Validate: `lib/features/ai_models/application/model_download_providers.dart`
- Validate: `test/features/ai_chat/presentation/ai_chat_page_test.dart`

- [ ] **Step 1: Add a failing catalog parsing test if a catalog test file already exists**

If there is already an existing model-catalog parsing test file, add a test that expects at least one LLM entry to load from the built-in catalog. If no such test file exists, skip this step and rely on the direct widget/provider validations in this plan.

- [ ] **Step 2: Add one minimal LLM catalog entry to `built_in_catalog.json`**

Append a second entry in `assets/model_catalog/built_in_catalog.json` shaped like this:

```json
{
  "id": "phi_local_q4",
  "type": "llm",
  "tier": "local",
  "display_name": "Phi Local Q4",
  "description": "用于本地自由聊天与首轮设备问答验证的轻量级本地 LLM。",
  "size_bytes": 104857600,
  "min_ram_mb": 2048,
  "recommended_tier": "local",
  "source_list": [
    {
      "id": "project-owned-primary",
      "label": "项目内置来源",
      "url": "https://example.invalid/models/phi_local_q4.gguf",
      "checksum": "sha256:replace-with-real-checksum"
    }
  ]
}
```

Replace the placeholder URL/checksum with the real values chosen for the repo. Keep the existing embedding entry unchanged.

- [ ] **Step 3: Verify `model_download_providers.dart` does not need broader changes**

Read the existing `type == 'llm'` post-download block and keep it unchanged unless a provider invalidation issue appears during testing. The relevant branch should continue to:

```dart
if (entry.type == 'llm') {
  final runtimeResult = await _ref.read(llmRuntimeBridgeProvider).ensureModelReady(
        modelId: entry.id,
        modelPath: result.localPath,
      );
  final runtimeState = mapLlmRuntimeState(runtimeResult, fallbackPath: result.localPath);
  final persisted = await _registryRepository.getById(entry.id);
  if (persisted != null) {
    await _registryRepository.save(
      persisted.copyWith(
        enabled: runtimeState.status == LlmRuntimeStatus.ready ||
            runtimeState.status == LlmRuntimeStatus.installedUnverified,
        filePresent: runtimeState.status != LlmRuntimeStatus.missing,
      ),
    );
  }
}
```

Do not add auto-selection here.

- [ ] **Step 4: Run focused tests covering providers and model-management UI**

Run:

```powershell
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected:

- Both test files pass.

- [ ] **Step 5: Run a focused `/ai/chat` consumer regression test**

Run:

```powershell
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart --plain-name "AI chat page shows jump-to-model-management CTA when llm is unavailable"
flutter test test/features/ai_chat/presentation/ai_chat_page_test.dart --plain-name "free chat renders first local response after sending a message"
```

Expected:

- Existing `/ai/chat` readiness and first-response tests still pass.

- [ ] **Step 6: Run analyzer validation for the touched scope**

Run:

```powershell
flutter analyze
```

Expected:

- No new analyzer errors in the changed files.

- [ ] **Step 7: Commit**

```bash
git add assets/model_catalog/built_in_catalog.json lib/features/ai_chat/application/llm_runtime_providers.dart lib/features/ai_models/presentation/model_management_page.dart test/features/ai_chat/application/llm_runtime_providers_test.dart test/features/ai_models/presentation/model_management_page_test.dart
git commit -m "feat: unblock local llm first generation selection flow"
```

---

## Self-Review Checklist

- [ ] The spec requirement for one built-in LLM catalog entry maps to Task 3.
- [ ] The spec requirement for an explicit local-LLM selection controller maps to Task 1.
- [ ] The spec requirement for a model-management activation affordance maps to Task 2.
- [ ] No task introduces Android runtime rewrites, chat orchestration rewrites, or automatic local-LLM selection policy.
- [ ] Every production change is preceded by a failing test except the catalog JSON addition, which is configuration data supporting already-tested flows.
- [ ] The exact preference key remains `ai.active_llm_model_id`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-01-local-llm-first-generation-device-loop.md`.

Two execution options:

**1. Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** - Execute tasks in this session using the plan directly, with checkpoints between the TDD phases.
