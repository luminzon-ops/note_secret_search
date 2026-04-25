# Model Summary Alignment Design

## Background

The Android-first Flutter MVP now exposes richer active-model capability text in `SearchSettingsPage`, including version, model size, minimum RAM, and recommended tier. However, the model-management experience still presents related information in a different shape: catalog entries use separate chips, while the installed-model list only shows the local path and a coarse status label.

This inconsistency creates avoidable friction. Users can see a compact capability summary in search settings, then switch to the model page and lose that same high-signal summary. The next MVP slice should align those two surfaces without expanding into download flow, selection logic, or broader model deployment architecture.

## Goals

1. Align model capability summary wording between `SearchSettingsPage` and the model-management page.
2. Add one short deployment-status line that helps users understand whether a model is locally usable.
3. Keep the implementation conservative and presentation-focused.
4. Preserve current page structure and existing download / selection behavior.
5. Cover the change with focused widget tests.

## Non-Goals

1. No new model-installation workflow.
2. No changes to download state machines or retry behavior.
3. No new provider, service, or domain-layer state.
4. No redesign of the model catalog into detailed cards or multi-step setup flows.
5. No attempt to fully unify every model-related UI into a shared component system.

## User Problem

Two nearby surfaces describe the same models differently:

1. `SearchSettingsPage` now shows a compact, readable capability summary for the active embedding model.
2. `ModelManagementPage` shows a mixture of path text, chips, and status labels, but not the same summary string.

That means users cannot easily compare what they selected in search settings with what is installed and available in model management. It also weakens the local-first deployment story because model-management surfaces do not clearly say whether the model is ready for local use.

## Chosen Approach

Use the `SearchSettingsPage` summary format as the baseline and align the model-management page to it. Add one extra deployment-status line per relevant model-management surface, using only information already available in the existing UI state.

This achieves consistency with minimal scope growth. It improves user understanding while avoiding changes to model download, indexing, or activation logic.

## Alternatives Considered

### 1. Align summary only (not chosen)

- Reuse the same capability summary string in both pages.
- Do not add any deployment-status explanation.

Rejected because:

- It improves consistency, but still leaves the model page weak on “can I use this locally right now?” messaging.
- The user explicitly selected the richer option with a deployment-status line.

### 2. Align summary + add one deployment-status line (chosen)

- Reuse one compact capability summary shape.
- Add one short human-readable deployment line using existing installed / active / file-present information.

Why chosen:

- Still conservative.
- Stronger user-facing clarity.
- No new architecture required.

### 3. Build a shared reusable model-info widget system (not chosen)

- Extract summary, chips, and deployment state into common presentation widgets.

Rejected because:

- Too much abstraction for the current MVP tranche.
- Increases scope and refactor risk.
- The immediate problem is consistency, not component architecture.

## Detailed Behavior

### Capability summary format

When a model summary is shown in either page, it should use the same compact order:

1. provider
2. type
3. quantization, if present
4. `版本 <version>`, if present
5. human-readable size, if present
6. `RAM ≥ <minRamMb>MB`, if present
7. `推荐档位 <recommendedTier>`, if present

Examples:

- `builtin · embedding · Q8 · 版本 1.0.2 · 10.0 MB · RAM ≥ 512MB · 推荐档位 mvp`
- `builtin · embedding`

Missing metadata is omitted rather than replaced by placeholders.

### Search settings page behavior

`SearchSettingsPage` already shows the richer capability summary for `readiness.activeEmbeddingModel`.

For this tranche, it should additionally show one short deployment-status line immediately below the summary text and above the existing explanatory sentence. The line should remain compact and use only existing local model state.

Preferred behavior:

- If the active embedding model is installed and the file is present, show:
  - `部署状态：本地文件已就绪，可用于当前语义检索。`
- If the active embedding model record exists but the file is missing, show:
  - `部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。`

This line should not attempt to describe indexing status, runtime warmup, or download source health.

### Model management page behavior

The model-management page has two relevant surfaces:

1. Installed-model list (`_InstalledModelsCard`)
2. Catalog entry tiles (`_CatalogEntryTile`)

For this tranche:

#### Installed models card

Each installed model row should become slightly more informative while keeping the card compact:

- Keep the title as the model name.
- Replace or expand the subtitle so it includes:
  1. the aligned capability summary line
  2. one deployment-status line
- The local path may remain available, but should not crowd out the new summary. If necessary, it can move to a tertiary line or remain omitted from the main compact slice.

Deployment-status wording should be driven by existing registry state:

- If `entry.isInstalled == true` and `entry.filePresent == true`:
  - `部署状态：本地文件已就绪。`
- If `entry.isInstalled == false` or `entry.filePresent == false`:
  - `部署状态：本地文件缺失，当前记录不可直接使用。`
- If the entry is also the active embedding model:
  - Append active context in the trailing label or deployment line, but do not add a second independent status block.
  - Example acceptable result:
    - trailing: `当前语义模型`
    - deployment line: `部署状态：本地文件已就绪。`

#### Catalog entry tile

Catalog tiles already expose detailed metadata via chips. To keep the tranche conservative, they should not be redesigned into fully new layouts.

The chosen behavior is:

- Keep the existing chips for tier / recommended tier / RAM / size.
- Add one compact deployment-status line beneath the description or metadata area using installed state already available in the tile.

Suggested wording:

- If the model is installed and file-present:
  - `部署状态：已下载到本地，可立即用于后续启用或检索配置。`
- If the model is not installed:
  - `部署状态：尚未下载到本地。`
- If the registry entry exists but is not file-present:
  - `部署状态：本地记录存在，但文件缺失，需要重新下载。`

This keeps the catalog useful without forcing a larger summary refactor there.

## Interaction Model

1. No new interactions are added.
2. Existing download, delete, retry, and selection buttons remain unchanged.
3. This tranche is purely about presentation consistency and readiness clarity.

## Technical Design

### Files expected to change

- `lib/features/search/presentation/search_settings_page.dart`
- `lib/features/ai_models/presentation/model_management_page.dart`
- `test/features/search/presentation/search_settings_page_test.dart`
- Add: `test/features/ai_models/presentation/model_management_page_test.dart`

### Likely code changes

1. Keep or lightly refactor the existing summary formatter in `search_settings_page.dart`.
2. Reuse the same summary logic in the model-management page with the smallest reasonable extraction strategy.
3. Add a tiny deployment-status formatter for search-settings active model state.
4. Add a tiny deployment-status formatter for model-management installed / catalog state.
5. Keep all formatting logic in presentation code unless a tiny shared presentation helper is clearly lower-risk than duplication.

### Extraction rule

If a shared helper is introduced, it should stay narrowly presentation-oriented and only cover:

- capability summary formatting
- deployment-status sentence formatting

It should not become a new domain abstraction or UI framework layer.

## Error Handling

1. If async providers are loading, existing loading behavior remains unchanged.
2. If model records are missing, the page should continue to render existing empty/error states.
3. Missing metadata must be omitted from summaries instead of showing fake fallback text.
4. Deployment-status lines may use conservative wording, but must not overclaim runtime readiness or security guarantees.

## Testing Strategy

Use TDD.

### Search settings page tests

Add or update tests to verify:

1. Active model summary still shows the aligned summary text.
2. Installed active model shows the ready deployment-status line.
3. Active model record with missing local file shows the degraded deployment-status line.

### Model management page tests

Add focused widget tests for:

1. Installed model entry shows the aligned capability summary.
2. Installed file-present model shows `部署状态：本地文件已就绪。`
3. Missing-file registry entry shows `部署状态：本地文件缺失，当前记录不可直接使用。`
4. Catalog tile shows the correct deployment-status line for installed vs not-installed states.

Tests should remain narrow and avoid coupling to unrelated download or routing behavior.

### Verification

- Run targeted widget tests for search settings.
- Run targeted widget tests for model management.
- Run `flutter analyze`.
- Run diagnostics on changed files.

## Constraints Carried Forward

1. Password-manager-first product.
2. Android-first MVP.
3. No attachment work in v1.
4. No multi-vault UI exposure.
5. No master password.
6. Semantic retrieval remains local-first and privacy-first.
7. Do not overclaim model readiness beyond what local file presence and current selection can prove.

## Implementation Readiness

This design is intentionally narrow. It is ready for a small TDD-first implementation tranche that aligns summary wording across the two pages and adds one lightweight deployment-status line without altering core behavior.

## Git Note

The brainstorming workflow normally asks for committing the design doc, but this session will not create a git commit unless the user explicitly requests one.
