# Model Management Status Copy Design

## Background

`ModelManagementPage` already exposes the core states users need for the Android-first Flutter MVP: installed-model status, active semantic-model status, local deployment readiness, and download-task progress. However, these states are currently described through multiple local wording systems spread across trailing labels, chips, deployment-status sentences, and download-task text.

The result is understandable, but not yet cohesive. Users can see labels such as `当前语义模型`, `已安装`, `记录失效`, `已启用`, `尚未下载`, and multiple download-task phrases that do not clearly belong to one unified naming system.

This slice standardizes status copy inside `ModelManagementPage` only. It does not change behavior, state derivation, or page structure.

## Goals

1. Unify model-management status wording into one coherent semantic system.
2. Make degraded local state more explicit by replacing ambiguous wording like `记录失效`.
3. Keep the page behavior unchanged.
4. Limit the work to `ModelManagementPage` presentation semantics.
5. Cover the wording changes with focused widget tests.

## Non-Goals

1. No provider, repository, service, or domain-layer changes.
2. No new state machine or status enum.
3. No button-text changes such as `开始下载`, `删除本地模型`, or `设为语义模型`.
4. No SearchSettingsPage copy changes in this tranche.
5. No layout redesign.

## User Problem

The same underlying model state is currently described with multiple overlapping phrases depending on where the user looks:

1. Installed-model rows use trailing labels like `当前语义模型`, `已安装`, and `记录失效`.
2. Catalog tiles use top chips like `已启用` and `已安装`.
3. Deployment-status lines use full-sentence explanations like `部署状态：已下载到本地...` or `部署状态：本地记录存在，但文件缺失...`.
4. Download-task cards use another vocabulary such as `本地模型已安装`, `尚未创建下载任务`, and `任务状态：下载中`.

These phrases are individually understandable, but collectively they do not form one stable status language.

## Chosen Approach

Unify the copy across all status-bearing parts of `ModelManagementPage` while leaving the underlying logic untouched. This means different UI locations may still render labels, chips, or sentences, but they should all derive from the same semantic vocabulary.

The goal is copy consistency, not UI unification.

## Alternatives Considered

### 1. Only rename `记录失效` (not chosen)

- Change only the most ambiguous label.

Rejected because:

- It improves one pain point but leaves the broader wording system fragmented.

### 2. Unify primary labels only (not chosen)

- Align trailing labels and top chips.
- Leave deployment and download-task text as-is.

Rejected because:

- It still leaves two or three independent vocabularies on the same page.

### 3. Unify all model-management status copy while preserving behavior (chosen)

- Align row labels, top chips, deployment sentences, and download-task wording.
- Do not change buttons, logic, or layout.

Why chosen:

- Creates a coherent status language.
- Still limited to one page and one concern: copy.
- Improves clarity without architecture changes.

## Detailed Behavior

### Status semantics

The page should consistently describe four kinds of state:

1. **Role state** — whether this model is the currently selected semantic model.
2. **Local availability state** — whether a local file is ready, missing, or not downloaded.
3. **Deployment explanation** — a short sentence explaining the local state.
4. **Download task state** — what the current or latest download task is doing.

### Unified wording system

#### 1. Role labels

These identify how the model participates in the current search setup:

- `当前语义模型`
- `已安装模型`

Rules:

- If an installed model is the current active embedding model, prefer `当前语义模型`.
- If a model is locally available but not active, use `已安装模型` instead of the shorter `已安装`.

#### 2. Degraded local state label

Replace ambiguous wording:

- Old: `记录失效`
- New: `本地记录失效`

Reasoning:

- The user should understand that the problem is not a generic broken record, but specifically that the local model record exists while the local file is no longer directly usable.

#### 3. Not-downloaded state

When the model exists only in the catalog and has not yet been downloaded locally, use wording centered on:

- `尚未下载`

This may appear either as a short chip/label or inside the deployment sentence, but the core phrase should stay consistent.

#### 4. Deployment sentences

Deployment-status text should use the same local-state vocabulary throughout the page.

Preferred sentence set:

- Ready:
  - `部署状态：本地已就绪，可用于后续启用或检索配置。`
- Not downloaded:
  - `部署状态：尚未下载到本地。`
- Degraded:
  - `部署状态：本地记录存在，但文件缺失，需要重新下载。`

The installed-model list may keep a shorter sentence if needed for compactness, but the keywords must align with the same vocabulary:

- `本地已就绪`
- `本地记录失效`
- `尚未下载`

#### 5. Download-task copy

Download-task wording should align with the same status language while remaining task-specific.

Suggested terminology:

- `本地模型已安装` → may remain if paired consistently with `本地已就绪`
- `尚未创建下载任务` → normalize toward a clearer phrase such as `下载任务未开始`
- `任务状态：下载中 / 已暂停 / 已完成 / 失败` → keep the task-state prefix if helpful, but make the terminology consistent with the page-wide vocabulary

This slice may keep the current `任务状态：...` structure if it improves clarity and avoids unnecessary churn.

## Interaction Model

No interactions change in this slice.

- No new buttons
- No new actions
- No button renames
- No new chips with behavior

Only the displayed wording changes.

## Technical Design

### Files expected to change

- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `lib/features/ai_models/presentation/model_presentation_formatter.dart` (if status wording helpers are expanded)
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Possibly add or update helper-level formatter tests if wording is centralized there

### Implementation preference

Prefer centralizing status wording in the existing shared presentation helper when the same wording is used in multiple parts of the page.

If some phrases remain page-local, they should still follow the same vocabulary and naming rules.

### Refactor rule

Change copy only. Do not change:

- status conditions
- provider reads
- active-model selection logic
- download-task logic
- widget hierarchy beyond what is necessary to swap strings

## Error Handling

1. Existing error and loading states remain unchanged unless their wording is explicitly part of the chosen status vocabulary.
2. The slice must not introduce fallback placeholders or generic unknown-state labels.
3. If a current phrase already maps clearly to the unified vocabulary, it may remain unchanged to reduce churn.

## Testing Strategy

Use TDD.

### Widget tests to add or update

Verify at least these cases:

1. Active installed model row shows `当前语义模型`.
2. Installed but inactive model row shows `已安装模型`.
3. Degraded installed-model row shows `本地记录失效`.
4. Catalog tile / deployment copy uses `尚未下载` consistently for not-downloaded state.
5. Degraded catalog state uses `本地记录存在，但文件缺失，需要重新下载。`
6. Any renamed download-task wording remains accurate and is covered by focused expectations.

### Verification

- Run `ModelManagementPage` widget tests.
- Run any helper-level formatter tests that changed.
- Run `flutter analyze`.
- Run diagnostics on changed files.

## Constraints Carried Forward

1. Password-manager-first product.
2. Android-first MVP.
3. No attachment work in v1.
4. No multi-vault UI exposure.
5. No master password.
6. This slice is wording-only and must not expand into logic changes.

## Implementation Readiness

This design is focused enough for a single TDD-first implementation tranche. It stays within one page, one concern, and one class of change: status copy semantics.

## Git Note

The brainstorming workflow normally asks for committing the design doc, but this session will not create a git commit unless the user explicitly requests one.
