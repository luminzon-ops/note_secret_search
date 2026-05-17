# Milestone 6-B Auto Failover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic source failover and lightweight source probing/sorting so model downloads can retry healthy fallback mirrors without breaking Milestone 6-A resume semantics.

**Architecture:** Keep `ModelDownloadService` as a single-source download primitive and introduce a small probe helper that returns ephemeral source facts. Extend `ModelDownloadController` to orchestrate candidate ordering, same-source-only resume, cross-source restart, and source-aware task persistence. Update the model management page so source-specific controls and status display no longer rely on a single model-level latest task.

**Tech Stack:** Flutter, Dart, Riverpod, Dio, `dart:io`, flutter_test.

---

## File Map

### New files
- `lib/features/ai_models/infrastructure/model_source_probe_service.dart`
- `test/features/ai_models/infrastructure/model_source_probe_service_test.dart`

### Existing files to modify
- `lib/features/ai_models/application/model_download_providers.dart`
- `lib/features/ai_models/infrastructure/model_download_service.dart` (only if minor probe-adjacent shared helpers are needed)
- `lib/features/ai_models/presentation/model_management_page.dart`
- `test/features/ai_models/application/model_download_providers_test.dart`
- `test/features/ai_models/presentation/model_management_page_test.dart`

### Docs created in this slice
- `docs/superpowers/specs/2026-04-30-milestone-6b-auto-failover-design.md`
- `docs/superpowers/plans/2026-04-30-milestone-6b-auto-failover.md`

### No schema changes
- Keep `ModelDownloadTask` and `download_tasks` unchanged.
- Do not persist probe results or retry history.

---

### Task 1: Add lightweight source probe helper

**Files:**
- Create: `lib/features/ai_models/infrastructure/model_source_probe_service.dart`
- Create: `test/features/ai_models/infrastructure/model_source_probe_service_test.dart`

- [ ] **Step 1: Write failing tests for lightweight probe behavior**

Cover at least:

```dart
test('probeSource marks source reachable from HEAD and reads content length', () async {})
test('probeSource falls back to GET range probe when HEAD is not useful', () async {})
test('rankSources keeps original order when probe facts tie', () async {})
```

- [ ] **Step 2: Run the new probe tests to verify RED**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/model_source_probe_service_test.dart
```

Expected: FAIL because the probe helper does not exist yet.

- [ ] **Step 3: Implement the minimal probe helper**

Add:

1. `ModelSourceProbeResult` DTO
2. `ModelSourceProbeService.probeSource(ModelSourceEntry source)`
3. a simple ranking helper that sorts fallback sources by:
   - reachable first
   - matching/known content length next
   - likely range support next
   - lower latency next
   - original order last

- [ ] **Step 4: Re-run probe tests to verify GREEN**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/model_source_probe_service_test.dart
```

Expected: PASS.

---

### Task 2: Extend controller orchestration for automatic source failover

**Files:**
- Modify: `lib/features/ai_models/application/model_download_providers.dart`
- Modify: `test/features/ai_models/application/model_download_providers_test.dart`

- [ ] **Step 1: Write failing controller tests for failover workflow**

Cover at least:

```dart
test('startDownload retries next source when selected source fails with failover-eligible error', () async {})
test('startDownload resets resumeFromBytes to zero when switching to a different source', () async {})
test('startDownload keeps same-source resume semantics for retried selected source', () async {})
test('startDownload stops failover on terminal local failure', () async {})
test('startDownload marks all sources failed when every source attempt fails', () async {})
test('markFailed updates only the specified source task row', () async {})
```

- [ ] **Step 2: Run the controller tests to verify RED**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
```

Expected: FAIL because source failover/orchestration and source-aware failure helpers do not exist yet.

- [ ] **Step 3: Implement minimal failover workflow in `ModelDownloadController`**

Implementation rules:

1. selected source always first attempt
2. remaining sources sorted by ephemeral probe result
3. same-source retry may resume from partial bytes
4. cross-source failover must restart from zero bytes
5. switching sources may delete the shared target file before retrying
6. checksum / rate-limit / timeout / 5xx are failover-eligible
7. user pause, invalid checksum config, malformed URL, local FS failure are terminal
8. source-aware helpers update rows by `modelId + sourceId`, not by `modelId` alone

- [ ] **Step 4: Re-run controller tests to verify GREEN**

Run:

```powershell
flutter test test/features/ai_models/application/model_download_providers_test.dart
```

Expected: PASS.

---

### Task 3: Make model management UI source-aware for task display and controls

**Files:**
- Modify: `lib/features/ai_models/presentation/model_management_page.dart`
- Modify: `test/features/ai_models/presentation/model_management_page_test.dart`

- [ ] **Step 1: Write failing widget tests for source-aware task display**

Cover at least:

```dart
testWidgets('ModelManagementPage prefers active downloading task over stale failed task from another source', (tester) async {})
testWidgets('ModelManagementPage binds source-specific controls to the selected or active source task', (tester) async {})
testWidgets('ModelManagementPage shows current source label from the active failover task', (tester) async {})
```

- [ ] **Step 2: Run the widget tests to verify RED**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: FAIL because the page still relies on model-level latest-task assumptions.

- [ ] **Step 3: Implement minimal source-aware UI selection**

Implementation rules:

1. distinguish selected-source task from overall display task
2. prefer active downloading task for model-level headline/status card
3. pause/retry/source label should operate on the selected or active source task, not an arbitrary latest model task
4. keep manual dropdown and existing button semantics
5. add only minimal new failover wording

- [ ] **Step 4: Re-run widget tests to verify GREEN**

Run:

```powershell
flutter test test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: PASS.

---

### Task 4: Run focused verification and stabilize regressions

**Files:**
- Verify: `test/features/ai_models/infrastructure/model_source_probe_service_test.dart`
- Verify: `test/features/ai_models/application/model_download_providers_test.dart`
- Verify: `test/features/ai_models/presentation/model_management_page_test.dart`
- Verify: `lib/features/ai_models/application/model_download_providers.dart`
- Verify: `lib/features/ai_models/presentation/model_management_page.dart`
- Verify: `lib/features/ai_models/infrastructure/model_source_probe_service.dart`

- [ ] **Step 1: Run the focused ai_models test suite**

Run:

```powershell
flutter test test/features/ai_models/infrastructure/model_download_service_test.dart test/features/ai_models/infrastructure/model_source_probe_service_test.dart test/features/ai_models/application/model_download_providers_test.dart test/features/ai_models/presentation/model_management_page_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: no new errors or warnings caused by this slice.

- [ ] **Step 3: Fix only slice-caused regressions and re-run verification**

If any test/analyze issue is introduced by 6-B, fix it minimally and rerun the relevant command until clean.

- [ ] **Step 4: Oracle review before completion claim**

Ask Oracle to review:

1. same-source-only resume rule
2. cross-source restart behavior
3. source-aware task selection cleanup
4. whether UI semantics stay minimal and correct

Expected: Oracle accepts the slice or identifies only actionable issues caused by this work.

---

## Self-Review Notes

- Spec coverage: probe helper, controller failover, UI task selection cleanup, and verification are all represented.
- Placeholder scan: no schema work, no persistent probe history, no broad refactor tasks.
- Type consistency: source-aware behavior stays keyed by `modelId + sourceId`; `ModelDownloadService` remains single-source.
