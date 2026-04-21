# Search Settings Blocked-State Guidance Design

## Background

The Android-first Flutter MVP already exposes a dedicated `SearchSettingsPage` for semantic-search readiness, index status, index settings, and search-scope controls. The page currently explains whether the local semantic pipeline is complete, but blocked states still require too much user interpretation.

This design adds lightweight guidance actions for the blocked semantic pipeline without expanding scope beyond the MVP. The goal is to shorten the path from diagnosis to recovery while keeping the existing compact settings layout.

## Goals

1. Keep the current `SearchSettingsPage` structure intact.
2. Turn blocked semantic readiness into clear next actions.
3. Only show executable actions when the underlying state actually allows them.
4. Preserve privacy-first, local-first MVP behavior.
5. Reuse existing providers and controllers wherever possible.

## Non-Goals

1. No redesign of the search settings page into a multi-step wizard.
2. No new global state management layer.
3. No new semantic engine capabilities.
4. No external-model flow changes.
5. No Android-native implementation changes in this tranche.

## User Problem

When local semantic retrieval is not ready, users can see that the pipeline is blocked, but they still need to infer what to do next. This is especially weak for three MVP-critical situations:

1. No active embedding model is selected.
2. Local semantic retrieval is disabled in search scope.
3. The index can be built or refreshed, but the page does not offer a direct action from the diagnostic area.

## Chosen Approach

Use the existing `下一步建议` area inside the semantic readiness card and extend it with lightweight chips or action chips.

This keeps the page compact, fits the current UI direction, and avoids adding heavy new containers or bottom action bars.

## Alternatives Considered

### 1. Lightweight guidance chips (chosen)

- Reuse the current diagnostics card and recommendation area.
- Add navigation actions or inline action chips based on blocked state.
- Minimal layout change.

Why chosen:

- Lowest implementation cost.
- Best fit for MVP.
- Preserves current page information hierarchy.

### 2. Per-stage CTA cards

- Each pipeline stage would render its own detailed CTA row or card.

Rejected because:

- Heavier UI.
- More vertical space.
- Adds presentation complexity without enough MVP value.

### 3. Unified bottom action area

- Show one or two primary actions at the bottom of the page.

Rejected because:

- Weakens the connection between a blocked stage and its recovery action.
- Less explainable than inline recommendations.

## Detailed Behavior

### Pipeline stages remain unchanged

The page continues to show the current three-stage summary:

1. Model selection
2. Local semantic scope
3. Index readiness

The wording of the stage summaries remains diagnostic-first and should stay compact.

### Guidance rules

#### 1. Missing active embedding model

Condition:

- `readiness.activeEmbeddingModel == null`

UI behavior:

- Show a clickable recommendation chip labeled `前往模型管理`.
- Clicking it navigates to `/models`.

Reasoning:

- Model selection is the most direct fix for this blocked state.

#### 2. Local semantic retrieval disabled

Condition:

- `scope.allowLocalEmbedding == false`

UI behavior:

- Show a non-navigating guidance chip labeled `启用本地语义检索`.
- This stays informational only in this tranche.

Reasoning:

- The toggle already exists on the same page.
- Adding scroll-to-section or automatic toggling is unnecessary complexity for MVP.

#### 3. Index is actionable

Condition:

- `indexStatus.readyForIndexing == true`
- `indexStatus.pendingItems.isNotEmpty == true`

UI behavior:

- Show a clickable recommendation chip labeled `立即构建索引` or `刷新本地索引`.
- Clicking it triggers `ref.read(searchIndexControllerProvider).indexPending()`.

Label rule:

- Use `立即构建索引` when there has not been a prior completed indexing task.
- Use `刷新本地索引` when `indexStatus.taskState.lastCompletedAt != null`.

Reasoning:

- This exposes a short recovery path exactly when the action is valid.

#### 4. Index is not actionable

Condition:

- `indexStatus.readyForIndexing == false`, or
- `indexStatus.pendingItems.isEmpty == true`

UI behavior:

- Do not show an index action in the `下一步建议` area.

Reasoning:

- Avoid misleading the user with an action that cannot succeed or is unnecessary.

## Interaction Model

1. The diagnostic summary remains the primary status surface.
2. The recommendations below it act as compact, contextual recovery shortcuts.
3. Navigation actions use `context.push(...)`.
4. Index actions call the existing search index controller directly.

## Technical Design

### Files expected to change

- `lib/features/search/presentation/search_settings_page.dart`
- `test/features/search/presentation/search_settings_page_test.dart`

### Likely code changes

1. Expand `_blockedGuidanceItems()` so it can derive index guidance in addition to model and scope guidance.
2. Represent guidance items with enough metadata to support either navigation or imperative action.
3. Convert `_SemanticReadinessCard` from `StatelessWidget` to `ConsumerWidget` if needed so it can dispatch indexing directly.
4. Keep `_IndexStatusCard` behavior unchanged except where duplicate wording would conflict with the new guidance area.

### Data shape expectations

The guidance-item model should support:

- `label`
- optional route target
- optional tap callback kind for local actions

Only one action type should be active for a single item.

## Error Handling

1. If provider data is still loading, no extra guidance is rendered beyond existing page behavior.
2. If the indexing action is triggered, existing controller behavior remains responsible for task execution and error propagation.
3. This tranche does not add new transient banners, snackbars, or retries.

## Testing Strategy

Use TDD.

### Widget tests to add or update

1. Missing model + local semantic disabled
   - shows `前往模型管理`
   - shows `启用本地语义检索`

2. Ready for indexing with pending items and no prior completed task
   - shows `立即构建索引`

3. Ready for indexing with pending items and prior completed indexing task
   - shows `刷新本地索引`

4. Not ready for indexing
   - does not show index action in the guidance area

5. Tapping index action
   - calls the search index controller once

6. Tapping model-management guidance
   - navigates to `/models`

### Verification

- Run targeted widget tests for `search_settings_page_test.dart`.
- Run `flutter analyze`.
- Run `lsp_diagnostics` on changed files.

## Constraints Carried Forward

1. Password-manager-first product.
2. Android-first MVP.
3. No attachment work in v1.
4. No multi-vault UI exposure.
5. No master password.
6. Semantic retrieval remains local-first and privacy-first.
7. Do not claim complete security or complete AI capability where the implementation is still placeholder-based.

## Implementation Readiness

This design is intentionally narrow and ready for a small TDD-first implementation tranche focused on `SearchSettingsPage` guidance actions only.

## Git Note

The brainstorming workflow normally asks for committing the design doc, but this session will not create a git commit unless the user explicitly requests one.
