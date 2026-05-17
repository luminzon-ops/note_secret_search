# Model Catalog Real Source Design

**Goal:** Continue Phase 1 Milestone 6 by upgrading model download management from a placeholder built-in catalog to a realistic embedding catalog with manual source selection and source-aware download task handling.

**Status:** Design approved by user before implementation.

---

## 1. Scope

This design stays strictly inside `第一阶段产品进度报告.md` → **重心二：把模型下载管理从“可运行”推进到“可交付”**.

This slice covers:

1. Replacing the current placeholder built-in embedding catalog entry with a more realistic public embedding artifact strategy.
2. Allowing the user to manually choose a download source for a catalog entry.
3. Making download task lookup and retry/pause behavior source-aware, instead of only model-aware.
4. Keeping checksum verification active for the selected source.
5. Updating tests and Phase 1 report conclusions to reflect the new catalog/source behavior.

This slice explicitly does **not** cover:

1. Signature verification.
2. Download resume / range requests / partial file continuation.
3. Automatic source failover or source speed benchmarking.
4. Remote manifest fetching or dynamic server-side catalog sync.
5. Real public GGUF LLM distribution in this step.
6. Device benchmark or model tier auto-gating.

---

## 2. Current Constraints

The current codebase already supports:

1. Asset-backed built-in catalog loading from `assets/model_catalog/built_in_catalog.json`.
2. Manual download initiation from `ModelManagementPage`.
3. Download completion checksum verification.
4. Runtime verification after a successful download.
5. Registry persistence for installed models.

The main limitations found during exploration are:

1. `ModelManagementPage` renders all sources but always downloads from `entry.sources.first`.
2. Download task lookup is keyed by `modelId` only, which makes source switching ambiguous.
3. The built-in catalog still points at placeholder URLs and placeholder checksums.
4. The current UX does not expose which source is actively selected for a given catalog entry.

These constraints make the next safe step clear: keep the built-in catalog architecture, but upgrade it from placeholder source metadata to realistic source metadata and align the task model with source choice.

---

## 3. Recommended Approach

### Recommended option

Use a **realistic built-in embedding catalog + manual source selection + source-aware task lookup**.

Why this is the best next step:

1. It stays entirely inside Milestone 6 rather than jumping to another workstream.
2. It resolves the biggest local inconsistency: the UI already shows multiple sources, but the app ignores that at download time.
3. It avoids premature infrastructure work like remote catalogs or publishing pipelines.
4. It keeps the slice medium-sized and testable.
5. It prepares the codebase for later source failover without implementing failover now.

### Rejected alternatives

#### Alternative A: Only replace placeholder URL/checksum in `built_in_catalog.json`

This is too narrow because the code would still ignore extra sources and remain internally inconsistent.

#### Alternative B: Add source picker plus automatic source failover

This is too large for the next slice. It expands from user-controlled source choice into a download state-machine redesign.

#### Alternative C: Move straight to remote manifest / GitHub Releases API integration

This introduces a publishing workflow and runtime dependency that are not required for the next local Phase 1 step.

---

## 4. Design Overview

The next implementation slice will keep the asset-based catalog, but make it behave more honestly.

### 4.1 Catalog strategy

The built-in catalog remains the source of truth for now.

It will contain:

1. At least one realistic **embedding** model entry.
2. A `source_list` with at least two source records for that entry.
3. Realistic source metadata fields already supported by the app (`id`, `label`, `url`, `checksum`).

For this slice, “realistic” means:

1. The source metadata structure is valid for public artifact distribution.
2. The entry is no longer described as a fake placeholder.
3. The catalog is shaped so the UI and task model can exercise multi-source behavior.

If a truly stable public artifact cannot be safely committed during implementation, the fallback is to keep the source URLs non-placeholder but still under controlled project ownership, with real checksums generated from the chosen artifact.

### 4.2 Manual source selection

Each catalog entry tile in `ModelManagementPage` will expose a source selector.

Behavior:

1. If a model has one source, the selector can render as a passive label.
2. If a model has multiple sources, the user can switch the active source before starting a download.
3. Download, retry, and related CTA behavior must use the currently selected source, not `entry.sources.first`.

This is intentionally **manual only**. The app will not automatically switch to another source on failure in this slice.

### 4.3 Source-aware task handling

The repository/controller flow must stop treating “latest task for a model” as sufficient.

New behavioral rule:

1. A task action triggered for `(modelId, sourceId)` should resolve the latest task for the same `(modelId, sourceId)` pair.
2. Pause/retry/failure handling must stay aligned with the selected source.
3. A source switch should not silently resume or mutate a task created for a different source.

This is the core integrity fix behind the UI change. Without it, source selection is cosmetic.

### 4.4 Checksum behavior

Checksum verification remains mandatory.

Rules:

1. The selected source must provide a checksum.
2. The downloaded file must verify against that checksum.
3. A mismatch still fails the task and blocks registry write.
4. The registry stores the verified checksum for the successful source.

No checksum fallback or placeholder bypass will be introduced.

---

## 5. Component-Level Changes

### 5.1 `assets/model_catalog/built_in_catalog.json`

Change from a single placeholder embedding entry to a more realistic embedding entry that supports multiple sources.

Requirements:

1. Keep the current schema.
2. Add at least two sources for the chosen embedding entry.
3. Every source must have a unique `id`.
4. Every source must include a checksum.

### 5.2 `lib/features/ai_models/presentation/model_management_page.dart`

Add source selection UI for catalog entries.

Requirements:

1. The entry tile must know which source is selected.
2. The selected source label must be visible.
3. The download CTA must call the controller with the selected source.
4. Retry behavior must also use the selected source.
5. Existing installed-model and runtime-state rendering must remain unchanged.

### 5.3 `lib/features/ai_models/application/model_download_providers.dart`

Update task flow to behave per source.

Requirements:

1. `enqueueDownload`, pause, and related operations must operate on the correct `(modelId, sourceId)` task when applicable.
2. Starting a download from source B must not accidentally reuse source A's in-progress task.
3. Failure messages should remain source-agnostic in wording unless existing code already exposes source-specific text.

### 5.4 `lib/features/ai_models/infrastructure/sqlite_model_download_repository.dart`

Add repository support for source-aware latest-task lookup.

Requirements:

1. Keep the existing model-level lookup if it is still used elsewhere.
2. Add a source-aware lookup method instead of overloading unrelated behavior.
3. Use `updated_at DESC` ordering consistently so the newest task for the same `(modelId, sourceId)` pair wins.

### 5.5 Tests

Tests must prove both UI and controller behavior.

Required additions/updates:

1. Widget test: an entry with multiple sources can switch selected source.
2. Widget test: download action uses the selected source, not the first source.
3. Application test: two tasks for the same model but different sources do not collide.
4. Existing ai_models tests continue passing.

---

## 6. Data Flow

The new flow is:

1. Asset catalog loads one model entry with multiple sources.
2. `ModelManagementPage` initializes the tile with a selected source.
3. User changes source selection if desired.
4. User taps download.
5. Controller starts a task using `(modelId, selectedSource.id)`.
6. Repository lookup and task updates stay bound to that `(modelId, sourceId)` pair.
7. Download completes.
8. Checksum verification runs against the selected source checksum.
9. On success, runtime verification runs and registry is updated.
10. On failure, the task for that same `(modelId, sourceId)` becomes failed.

---

## 7. Error Handling

This slice keeps error handling conservative.

Rules:

1. If a selected source lacks a checksum, download must fail rather than degrade silently.
2. If the selected source URL fails, the task fails and remains retryable.
3. The app does not automatically switch to another source.
4. If a previously selected source disappears from the catalog entry, the UI should fall back to the first available source.

The last rule avoids stale UI state when catalog contents evolve.

---

## 8. Testing Strategy

Verification must stay close to the Phase 1 report's evidence model.

### Automated coverage

At minimum:

1. `test/features/ai_models/application/model_download_providers_test.dart`
2. `test/features/ai_models/presentation/model_management_page_test.dart`
3. `test/features/ai_models/application/model_selection_providers_test.dart`
4. `test/features/ai_models/infrastructure/asset_model_catalog_repository_test.dart`
5. `flutter analyze`

### Acceptance criteria

This slice is complete when:

1. A catalog entry can expose multiple sources.
2. The user can explicitly choose which source is used.
3. Download/retry flows honor the selected source.
4. Task lookup no longer ambiguously merges different sources for the same model.
5. Checksum verification still works for the chosen source.
6. The Phase 1 report is updated to reflect the new Milestone 6 status.

---

## 9. Out-of-Scope Follow-Ups

These are intentionally deferred, not forgotten:

1. Automatic source failover.
2. Resume / partial file continuation.
3. Signature verification.
4. Remote catalog publishing.
5. Multiple real embedding entries grouped by tier.
6. Real GGUF LLM public artifact distribution.
7. Benchmark-driven source/model recommendations.

---

## 10. Implementation Readiness

This design is focused enough for one implementation plan.

It changes only one workstream:

> **Milestone 6 → built-in catalog realism + source-aware download UX/infrastructure**

It does not require decomposing into multiple specs first.
