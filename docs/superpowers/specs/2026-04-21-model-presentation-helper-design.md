# Model Presentation Helper Design

## Background

The Flutter MVP now renders aligned model capability summaries and deployment-status text in both `SearchSettingsPage` and `ModelManagementPage`. That alignment was implemented directly inside the page files, which solved the user-facing inconsistency but left the same formatting logic duplicated across two presentation surfaces.

This next slice is a conservative cleanup. The goal is not to change any user-visible behavior, but to move duplicated presentation-only string formatting into one shared helper so future updates do not drift across pages again.

## Goals

1. Extract a shared pure-string presentation helper for model capability summary text.
2. Extract shared pure-string presentation helpers for deployment-status text.
3. Preserve all current page behavior and wording.
4. Keep the helper narrow, presentation-only, and easy to test.
5. Verify the refactor with focused tests and existing widget test suites.

## Non-Goals

1. No widget abstraction or shared UI component extraction.
2. No provider, service, repository, or domain-layer changes.
3. No wording changes to currently shipped summary or deployment-status strings.
4. No page layout changes.
5. No new model-management behavior or state transitions.

## User Problem

The current wording is aligned, but the formatting logic is duplicated in two page files:

1. `SearchSettingsPage` formats capability summary and active-model deployment status locally.
2. `ModelManagementPage` formats capability summary, installed-model deployment status, and catalog deployment status locally.

That duplication increases the chance of future drift. A small change to wording or field order could be applied in one page and forgotten in the other.

## Chosen Approach

Create one small presentation helper file containing pure functions that return `String` values only. Both pages will import and use that helper instead of maintaining local copies of the formatting logic.

This keeps the refactor extremely conservative: no new widgets, no cross-layer abstraction, and no new data shape. The helper only centralizes already-approved display text.

## Alternatives Considered

### 1. Extract summary helper only (not chosen)

- Move only the capability summary into shared code.
- Leave deployment-status logic inside each page.

Rejected because:

- It reduces only part of the duplication.
- Deployment-status wording is now also shared and can drift later.

### 2. Extract summary + deployment-status pure-string helpers (chosen)

- Move all duplicated string formatting into one small helper file.
- Keep all rendering and layout decisions inside the pages.

Why chosen:

- Smallest complete cleanup.
- Keeps the helper easy to understand and test.
- Preserves current behavior.

### 3. Extract a shared widget or presentation model layer (not chosen)

- Build reusable UI widgets or typed presenter objects for model display.

Rejected because:

- Too much abstraction for this MVP slice.
- Higher churn and higher regression risk.
- The current problem is duplicated string formatting, not UI composition.

## Detailed Behavior

### Helper scope

The helper should remain a single-purpose presentation utility and expose only pure functions.

Expected helper responsibilities:

1. Format capability summary for `ModelRegistryEntry`.
2. Format search-settings deployment status for the active embedding model.
3. Format installed-model deployment status for model-management installed rows.
4. Format catalog deployment status for model-management catalog rows.

It must not:

- depend on `BuildContext`
- return widgets
- read providers
- mutate state
- define new domain types

### Expected function shape

The exact file name may vary slightly to fit repo conventions, but the helper should expose functions equivalent to:

```dart
String formatModelCapabilitySummary(ModelRegistryEntry model);

String formatSearchSettingsDeploymentStatus(ModelRegistryEntry model);

String formatInstalledModelDeploymentStatus(ModelRegistryEntry entry);

String formatCatalogDeploymentStatus(ModelRegistryEntry? installedEntry);
```

### Capability summary behavior

`formatModelCapabilitySummary(ModelRegistryEntry model)` must preserve the current approved order exactly:

1. provider
2. type
3. quantization, if present
4. `版本 <version>`, if present
5. human-readable size, if present
6. `RAM ≥ <minRamMb>MB`, if present
7. `推荐档位 <recommendedTier>`, if present

Missing metadata continues to be omitted without placeholders.

### Deployment-status behavior

The helper must preserve the current wording exactly.

#### Search settings active model

- If `model.isInstalled`:
  - `部署状态：本地文件已就绪，可用于当前语义检索。`
- Otherwise:
  - `部署状态：模型记录仍在，但本地文件缺失，需要重新下载或修复。`

#### Installed model row

- If `entry.isInstalled`:
  - `部署状态：本地文件已就绪。`
- Otherwise:
  - `部署状态：本地文件缺失，当前记录不可直接使用。`

#### Catalog entry

- If `installedEntry == null`:
  - `部署状态：尚未下载到本地。`
- If `installedEntry.isInstalled`:
  - `部署状态：已下载到本地，可立即用于后续启用或检索配置。`
- Otherwise:
  - `部署状态：本地记录存在，但文件缺失，需要重新下载。`

## Interaction Model

No interactions change in this slice. All existing buttons, chips, and page flows remain untouched.

## Technical Design

### Files expected to change

- Create: `lib/features/ai_models/presentation/model_presentation_formatter.dart`
- Modify: `lib/features/search/presentation/search_settings_page.dart`
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Create: `test/features/ai_models/presentation/model_presentation_formatter_test.dart`
- Update existing widget tests only if imports or expectations need minimal adjustment

### Placement rationale

The helper should live in the `ai_models/presentation` area because:

1. the formatting is model-specific presentation logic
2. `ModelManagementPage` already belongs to that feature
3. `SearchSettingsPage` can depend on this helper without introducing domain coupling

This keeps the dependency direction acceptable for an MVP and avoids creating a new shared infrastructure layer for a tiny refactor.

### Refactor rule

Move logic, do not redesign logic.

That means:

- same strings
- same ordering
- same omission rules
- same page rendering structure

Only the location of the logic changes.

## Error Handling

1. The helper functions remain total for their supported inputs.
2. Missing optional fields continue to be omitted.
3. No fallback placeholders are introduced.
4. No additional runtime error handling is needed beyond existing page behavior.

## Testing Strategy

Use TDD.

### New helper-level tests

Add direct unit-style tests for:

1. capability summary with full metadata
2. capability summary with sparse metadata
3. search-settings deployment status for installed model
4. search-settings deployment status for missing-file model
5. installed-model deployment status for installed model
6. installed-model deployment status for degraded model
7. catalog deployment status for null entry
8. catalog deployment status for installed entry
9. catalog deployment status for missing-file entry

### Existing widget verification

Re-run:

1. `SearchSettingsPage` widget tests
2. `ModelManagementPage` widget tests

The widget output should remain unchanged.

## Constraints Carried Forward

1. Password-manager-first product.
2. Android-first MVP.
3. No attachment work in v1.
4. No multi-vault UI exposure.
5. No master password.
6. Semantic retrieval remains local-first and privacy-first.
7. This slice must remain behavior-preserving, not feature-expanding.

## Implementation Readiness

This design is intentionally tiny and ready for a TDD-first refactor slice. It is suitable for one implementation plan and should produce no user-visible change beyond keeping future wording consistent across pages.

## Git Note

The brainstorming workflow normally asks for committing the design doc, but this session will not create a git commit unless the user explicitly requests one.
