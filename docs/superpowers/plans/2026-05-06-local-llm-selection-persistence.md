# Local LLM Selection Persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix a startup race where `activeLocalLlmModelProvider` clears the shared-pref key (`ai.active_llm_model_id`) before `revalidateInstalledModel` has healed the registry/runtime state, causing AI chat to show no selected model.

**Architecture:** `activeLocalLlmModelProvider` (llm_runtime_providers.dart:63-85) currently removes the pref key whenever `runtimeState.ready` is false. The fix defers deletion when the model is degraded but the underlying file is present — the healing path (`revalidateInstalledModel` in model_download_providers.dart:706) will restore `runtimeState.ready` to true, after which the provider will converge correctly on the next read. The selected model ID is preserved in shared prefs through the degraded window.

**Tech Stack:** Flutter + Riverpod + SharedPreferences. Existing test suite in `test/features/ai_chat/application/llm_runtime_providers_test.dart`.

---

## Root Cause

```
App startup
└─ activeLocalLlmModelProvider evaluates
   ├─ reads storedModelId from SharedPrefs          ✓
   ├─ fetches modelRegistryEntriesProvider          ✓ (registry healed already)
   ├─ fetches llmRuntimeStatesProvider              ✗ (runtime probe → degraded/!ready)
   └─ if !runtimeState.ready → removes pref key     ← BUG: premature deletion
```

The registry entry is valid and file is present. The runtime probe returns `!ready` because the LLM runtime hasn't been initialized yet (degraded or installedUnverified). The provider deletes the pref key before `revalidateInstalledModel` can run and heal the runtime state.

---

## File Structure

- Modify: `lib/features/ai_chat/application/llm_runtime_providers.dart:63-85`
- Add test: `test/features/ai_chat/application/llm_runtime_providers_test.dart`

---

## Task 1: Add regression test — degraded runtime does NOT clear pref key

**Files:**
- Modify: `test/features/ai_chat/application/llm_runtime_providers_test.dart`

- [ ] **Step 1: Add test case**

Add the following test inside the `main()` function in `llm_runtime_providers_test.dart` (after line 197):

```dart
test('activeLocalLlmModelProvider does NOT clear pref when runtime is degraded but file is present', () async {
  SharedPreferences.setMockInitialValues({'ai.active_llm_model_id': 'llm-1'});
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
      modelRegistryEntriesProvider.overrideWith((ref) async => const [_llmModel]),
      llmRuntimeStatesProvider.overrideWith(
        (ref) async => {
          'llm-1': const LlmRuntimeState(
            ready: false,
            reason: 'session not yet initialized',
            status: LlmRuntimeStatus.degraded,
          ),
        },
      ),
    ],
  );

  addTearDown(container.dispose);

  final model = await container.read(activeLocalLlmModelProvider.future);
  final preferences = await container.read(sharedPreferencesProvider.future);

  // Model must be returned (not null) — the bug deletes the pref key when !ready
  expect(model?.id, 'llm-1');
  // Pref key must be preserved so revalidateInstalledModel can heal and provider converges
  expect(preferences.getString('ai.active_llm_model_id'), 'llm-1');
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd E:\Archive\Flutter\note_secret_search
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart --name "does NOT clear pref when runtime is degraded"
```
Expected: FAIL — `model` is `null` and pref key is also `null` (the bug behavior).

---

## Task 2: Fix activeLocalLlmModelProvider — preserve pref on degraded runtime

**Files:**
- Modify: `lib/features/ai_chat/application/llm_runtime_providers.dart:63-85`

- [ ] **Step 1: Apply minimal fix**

In `llm_runtime_providers.dart`, replace the block at lines 78-82:

```dart
  // BEFORE (buggy):
  final runtimeState = runtimeStates[selectedEntry.id] ?? _fallbackRuntimeState(selectedEntry);
  if (!runtimeState.ready) {
    await preferences.remove(_activeLlmModelIdKey);
    return null;
  }
```

With:

```dart
  // AFTER (fixed):
  final runtimeState = runtimeStates[selectedEntry.id] ?? _fallbackRuntimeState(selectedEntry);
  // Only clear the pref key when the model is truly uninstalled or missing from disk.
  // Degraded / installedUnverified / !ready states are healable by revalidateInstalledModel —
  // we must NOT delete the pref key prematurely so the healing path can converge.
  if (!runtimeState.ready &&
      runtimeState.status != LlmRuntimeStatus.degraded &&
      runtimeState.status != LlmRuntimeStatus.installedUnverified) {
    await preferences.remove(_activeLlmModelIdKey);
    return null;
  }
```

- [ ] **Step 2: Run the new regression test to verify it passes**

```bash
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart --name "does NOT clear pref when runtime is degraded"
```
Expected: PASS

- [ ] **Step 3: Run all llm_runtime_providers tests to verify no regressions**

```bash
flutter test test/features/ai_chat/application/llm_runtime_providers_test.dart
```
Expected: ALL PASS — including the existing test `'activeLocalLlmModelProvider keeps degraded selected llm model in preferences'` (line 147) which already verifies this scenario and must continue to pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/ai_chat/application/llm_runtime_providers.dart test/features/ai_chat/application/llm_runtime_providers_test.dart
git commit -m "fix(ai_chat): preserve active LLM selection in SharedPrefs when runtime is degraded

Previously activeLocalLlmModelProvider deleted the pref key whenever
runtimeState.ready was false, including degraded/installedUnverified states
that revalidateInstalledModel can heal. This caused startup race: the pref
was cleared before the healing path ran, making AI chat show no selected
model.

Now the provider only clears the pref when the model is truly
uninstalled or missing from disk (notInstalled/missing/corrupted). Degraded
and installedUnverified states preserve the pref so revalidateInstalledModel
can restore the runtime to ready, after which the provider converges.

Regression test added covering degraded runtime with file present."
```

---

## Verification Steps

1. **Run full test suite for affected providers:**
   ```bash
   flutter test test/features/ai_chat/ test/features/ai_models/
   ```

2. **Real-device verification (manual):**
   - Install a LLM model, set it as active, close the app.
   - Reopen the app — the model should still be selected in AI chat without "本地记录失效".
   - Long-press the model in Model Management → tap "校验" (revalidate) — after revalidation the runtime should become ready and AI chat functional.

---

## Risk Notes

- **Registry not yet healed at provider evaluation:** The fix is safe because `modelRegistryEntriesProvider` (which includes the healing/adoption path at model_download_providers.dart:40-86) resolves before `llmRuntimeStatesProvider`. So the registry entry is already normalized when the runtime probe runs. The only remaining gap is the runtime probe itself returning `!ready` for a file that's actually valid — which is exactly the degraded window `revalidateInstalledModel` addresses. Preserving the pref through this window is correct.

- **If `runtimeState.status` is `degraded` but the file is MISSING:** The `_fallbackRuntimeState` path (llm_runtime_providers.dart:154-187) correctly maps `!entry.filePresent` → `LlmRuntimeStatus.missing`, which is NOT in the excluded set, so the pref will still be cleared when the file is actually gone. This is correct behavior — a missing file can't be healed.

- **No behavior change for embedding models:** This fix only touches `activeLocalLlmModelProvider` / LLM path. The embedding path (`activeModelSelectionProvider`) has the same pattern but is out of scope for this bug report and was not observed to be affected.

- **No refactor of provider chain ordering:** The fix does not change the order of provider evaluation or introduce async gates. It's a single condition change in one provider.