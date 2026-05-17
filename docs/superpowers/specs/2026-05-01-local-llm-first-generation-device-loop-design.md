# Local LLM First Generation Device Loop Design

**Goal:** Unblock the first real on-device local LLM response in `/ai/chat` by adding the minimum prerequisites needed for one installed local LLM model to be discoverable, selectable, and usable by the existing chat runtime path.

**Status:** Direction approved. User explicitly allowed continuing without pausing for spec review.

---

## 1. Scope

This design stays strictly inside the current Phase 1 gap between an already-implemented local-first chat flow and the missing model-selection prerequisites that keep that flow from closing on a real device.

This slice covers exactly three required changes:

1. Add one built-in **LLM** catalog entry to `assets/model_catalog/built_in_catalog.json` so the model management flow can surface a downloadable local LLM artifact.
2. Add an **active local LLM selection controller/provider path** alongside the existing embedding-selection pattern so the app can intentionally persist `ai.active_llm_model_id`.
3. Add a **model-management activation affordance** in `lib/features/ai_models/presentation/model_management_page.dart` so an installed and runtime-ready local LLM can be marked as the current local LLM.

This slice explicitly does **not** cover:

1. Android runtime rewrites or backend replacement.
2. `/ai/chat` orchestration redesign.
3. Session persistence changes.
4. External provider changes or fallback-policy changes.
5. Automatic device-tier gating, benchmark logic, or source failover.
6. Automatic selection after download.
7. Multi-model local LLM management beyond selecting one active model.

---

## 2. Current Constraints

The current codebase already supports the downstream local-chat path that this slice needs to feed.

### 2.1 Existing chat/runtime path already exists

The following pieces are already present and should remain stable in this slice:

1. `/ai/chat` local-first backend resolution in `lib/features/ai_chat/application/ai_chat_providers.dart`.
2. Local LLM readiness aggregation in `lib/features/ai_chat/application/llm_runtime_providers.dart`.
3. Native runtime bridge and engine integration in:
   - `lib/features/ai_chat/infrastructure/llm_runtime_bridge.dart`
   - `lib/features/ai_chat/infrastructure/local_llm_engine.dart`
4. Android-side runtime/plugin code already exists and is already treated as a real consumer path.
5. Chat UI already exposes guidance to go to model management when local LLM readiness is missing.

This means the next safe step is **not** to re-implement chat. The missing work is upstream of chat.

### 2.2 The app already knows how to verify downloaded LLM models

`lib/features/ai_models/application/model_download_providers.dart` already contains a `type == 'llm'` branch that:

1. Calls `llmRuntimeBridgeProvider.ensureModelReady(...)` after download.
2. Maps the result through `mapLlmRuntimeState(...)`.
3. Persists the installed registry entry with readiness-derived `enabled` and `filePresent` flags.

So the download flow is already shaped for LLM verification once a catalog entry exists.

### 2.3 The built-in catalog currently exposes only embedding entries

`assets/model_catalog/built_in_catalog.json` currently contains a single `type: "embedding"` entry and no `type: "llm"` entry.

As a result:

1. Model management cannot offer a downloadable built-in local LLM.
2. The existing LLM post-download verification path is effectively unreachable from the built-in catalog UX.

### 2.4 Local LLM readiness reads a persisted selection, but there is no matching setter path

`lib/features/ai_chat/application/llm_runtime_providers.dart` already reads `ai.active_llm_model_id` through `activeLocalLlmModelProvider`.

Behavior already present:

1. If the stored model id is absent, the provider returns `null`.
2. If the selected registry entry disappears, the key is removed.
3. If the selected local LLM is installed but not runtime-ready, the key is also removed.

What is missing is the intentional write path that sets this preference in the first place.

### 2.5 Embedding selection already provides the reference pattern

`lib/features/ai_models/application/model_selection_providers.dart` already provides a complete pattern for embeddings:

1. `activeModelSelectionProvider`
2. `activeEmbeddingModelProvider`
3. `activeModelSelectionControllerProvider`
4. `setActiveEmbeddingModel(...)`

This is the correct design reference for local LLM selection in this slice.

### 2.6 Model management already renders LLM state, but stops short of LLM activation

`lib/features/ai_models/presentation/model_management_page.dart` already:

1. Reads `activeLocalLlmModelProvider`.
2. Renders `当前本地LLM` when an LLM is active.
3. Shows LLM runtime labels for installed LLM entries.

However, the catalog-card actions currently expose activation only for embeddings through `设为语义模型`.

That means the page can show an active local LLM marker if one is persisted externally, but it does not yet provide the normal UI path to create that state.

---

## 3. Recommended Approach

### Recommended option

Use a **minimal built-in local LLM catalog entry + explicit active-local-LLM selection controller + model-management activation CTA**.

Why this is the correct next step:

1. It stays tightly focused on the missing prerequisite layer rather than reopening already-working chat orchestration.
2. It reuses the codebase's existing embedding-selection conventions instead of inventing a second selection architecture.
3. It leverages the existing LLM post-download verification path instead of duplicating readiness logic.
4. It creates the smallest testable bridge between “downloaded LLM exists” and “`/ai/chat` can use it.”

### Rejected alternatives

#### Alternative A: Change `/ai/chat` to directly pick the first installed LLM

This is rejected because it bypasses explicit user choice, fights the existing `ai.active_llm_model_id` contract, and makes model-management state less honest.

#### Alternative B: Auto-activate an LLM immediately after download

This is rejected for this slice because:

1. The app already distinguishes between installed and runtime-ready.
2. Auto-selection introduces side effects that are harder to reason about and test.
3. The minimum requirement is explicit activation, not automatic policy.

#### Alternative C: Rework LLM selection into `model_selection_providers.dart`

This is rejected because the current LLM readiness and active-model reading live in `lib/features/ai_chat/application/llm_runtime_providers.dart`. Moving the whole concern would broaden the slice without delivering additional user value.

---

## 4. Design Overview

The design completes the missing upstream path that turns a built-in LLM artifact into a selectable local chat backend.

### 4.1 Catalog exposure

The built-in catalog remains asset-backed.

For this slice, it will gain:

1. One new `type: "llm"` entry.
2. Valid core metadata already understood by the app:
   - `id`
   - `type`
   - `tier`
   - `display_name`
   - `description`
   - `size_bytes`
   - `min_ram_mb`
   - `recommended_tier`
   - `source_list`
3. A realistic local-LLM description aligned with the existing product language.

The entry should stay minimal. This slice does not require tokenizer/runtime substructures because the existing LLM download path does not consume embedding-only tokenizer/runtime metadata.

### 4.2 Active local LLM selection

The app needs a deliberate write path for `ai.active_llm_model_id`.

The new controller/provider path should mirror the embedding pattern semantically:

1. A controller writes or clears the active LLM model id in `SharedPreferences`.
2. Relevant LLM readiness providers are invalidated after mutation.
3. The existing `activeLocalLlmModelProvider` continues to self-heal invalid selections.

The design goal is not to replace the current LLM providers, but to complete their missing write-side half.

### 4.3 Model-management activation affordance

The model management page should expose a local-LLM activation action in the same place users already manage download, deletion, and embedding activation.

Behavior:

1. The CTA appears only for `entry.type == 'llm'` catalog entries that are currently installed.
2. The CTA is enabled only when the installed LLM runtime state is `ready`.
3. Activating an already-active local LLM may clear the active selection, mirroring the embedding toggle semantics, or leave the active model selected if the implementation chooses the simpler no-op toggle. The chosen behavior must be explicit in tests.
4. The existing `当前本地LLM` marker remains the single source of truth for active-state display.

This keeps the model page honest: users can see a local LLM, verify it is ready, and explicitly choose it.

---

## 5. Component-Level Changes

### 5.1 `assets/model_catalog/built_in_catalog.json`

Add one built-in local LLM entry.

Requirements:

1. Keep the current asset-backed schema.
2. Preserve the existing embedding entry.
3. Add exactly one new `type: "llm"` entry for this slice.
4. Include at least one source in `source_list` with the metadata required by the existing download flow.
5. Avoid embedding-only metadata fields unless they are truly required for the chosen artifact.

### 5.2 `lib/features/ai_chat/application/llm_runtime_providers.dart`

Add the missing local-LLM selection write path.

Requirements:

1. Introduce a controller provider for active local LLM selection.
2. Add a `setActiveLocalLlmModel(String? modelId)` method.
3. Persist to `_activeLlmModelIdKey`.
4. Invalidate at least:
   - `activeLocalLlmModelProvider`
   - `localLlmReadinessProvider`
5. Keep the existing read-side self-healing behavior unchanged.

This file remains the LLM-specific owner of local-LLM readiness and selection semantics.

### 5.3 `lib/features/ai_models/presentation/model_management_page.dart`

Add a local-LLM activation affordance in the catalog entry actions.

Requirements:

1. Reuse existing page patterns rather than introducing a new card type.
2. Use the active local LLM provider/controller as the source of truth.
3. Gate activation to installed + runtime-ready LLM entries.
4. Keep embedding activation behavior unchanged.
5. Preserve existing installed-model summary, runtime-status copy, and download actions.

### 5.4 `lib/features/ai_models/application/model_download_providers.dart`

This file already performs LLM runtime verification after download and should only receive minimal follow-through changes if needed.

Requirements:

1. Keep the existing post-download `type == 'llm'` verification path.
2. Do not add auto-selection in this slice.
3. Only invalidate additional providers if the new local-LLM selection controller requires it.

### 5.5 Consumer validation only

The following files are consumers of this slice and should only be validated, not redesigned:

1. `lib/features/ai_chat/application/ai_chat_providers.dart`
2. `lib/features/ai_chat/presentation/ai_chat_page.dart`
3. `lib/features/ai_chat/presentation/chat_runtime_banner.dart`

They already depend on `localLlmReadinessProvider`, so once active local LLM selection becomes possible through normal UX, they should benefit without structural change.

---

## 6. Data Flow

The intended flow after this slice is:

1. The built-in catalog loads an embedding entry and one LLM entry from `assets/model_catalog/built_in_catalog.json`.
2. `ModelManagementPage` renders the new LLM catalog entry.
3. The user downloads the LLM entry using the existing download flow.
4. `model_download_providers.dart` stores the installed registry entry and runs `ensureModelReady(...)` for `type == 'llm'`.
5. If the runtime verification succeeds, the installed entry remains enabled and the runtime state becomes `ready`.
6. The user taps the new local-LLM activation CTA in `ModelManagementPage`.
7. The controller writes `ai.active_llm_model_id`.
8. `activeLocalLlmModelProvider` resolves the selected installed + ready LLM.
9. `localLlmReadinessProvider` becomes ready.
10. `/ai/chat` continues using its existing local-first backend resolution and can now complete the first real local generation loop on device.

---

## 7. Error Handling

This slice should preserve the existing self-healing posture rather than inventing new error-state models.

### 7.1 Invalid or degraded active selection

The existing behavior in `activeLocalLlmModelProvider` should remain authoritative:

1. If the selected model disappears, clear the preference.
2. If the selected model is no longer installed, clear the preference.
3. If the selected model is installed but not runtime-ready, clear the preference.

This prevents `/ai/chat` from treating a stale local LLM selection as valid.

### 7.2 Activation gating

The UI should not allow users to activate a local LLM that is:

1. Not installed.
2. Missing local files.
3. Corrupted.
4. Runtime-degraded.
5. Still unverified if the implementation treats unverified as not ready.

The page already has the runtime-state inputs required to enforce this.

### 7.3 No hidden auto-policy

This slice should avoid silent behaviors that make debugging harder, especially:

1. No automatic fallback selection of “the first available LLM.”
2. No automatic re-selection after delete/repair.
3. No automatic activation after download.

Explicit activation keeps the readiness story observable and testable.

---

## 8. Testing Scope

This slice must be proven primarily through provider and widget tests.

### 8.1 Provider tests

Update or extend `test/features/ai_chat/application/llm_runtime_providers_test.dart` to cover:

1. Setting an active local LLM id through the new controller path.
2. Clearing the active local LLM id.
3. Provider invalidation / re-read behavior after selection changes.
4. Continued self-healing when the selected LLM becomes degraded or missing.

### 8.2 Model management widget tests

Update or extend `test/features/ai_models/presentation/model_management_page_test.dart` to cover:

1. A ready installed LLM shows the local-LLM activation CTA.
2. Tapping the CTA updates the active local LLM state.
3. A degraded or non-ready installed LLM renders the CTA disabled.
4. Existing embedding activation behavior still works unchanged.

### 8.3 Chat consumer regression guard

Validate the existing `/ai/chat` widget coverage remains aligned, especially tests that already depend on `localLlmReadinessProvider` in `test/features/ai_chat/presentation/ai_chat_page_test.dart`.

This slice does not require new chat orchestration logic, but it should not regress the current local/unavailable behavior.

---

## 9. Non-Goals and Boundaries

To keep this slice small and shippable, the following are explicitly out of scope:

1. Changing the Android local runtime architecture.
2. Adding new LLM prompt construction behavior.
3. Reworking `/ai/chat` tabs or session persistence.
4. Moving all LLM selection into `model_selection_providers.dart`.
5. Supporting multiple simultaneously active local LLMs.
6. Device auto-tiering or capability detection.
7. Remote manifest/catalog infrastructure.
8. Source failover or download resume work beyond what already exists.

The success condition for this slice is narrow:

> A built-in local LLM can be downloaded, verified, explicitly activated in model management, and then recognized by the existing `/ai/chat` local-first path as the active local LLM for the first on-device generation loop.
