# Phase 0: Engineering Baseline Implementation Plan

> Parent Plan: `docs/2026-07-13-note-secret-search-v0-2-repair-roadmap.md`

## Goal

Establish a reproducible Flutter/Android engineering baseline before security and
runtime repairs begin. Production behavior remains unchanged in this phase except
for configuration and test-stability fixes.

## Scope

- Work only in the isolated `codex/repair-phase-0` worktree.
- Never modify the main worktree while implementing this plan.
- Use Flutter stable 3.41.5, Dart 3.11.3, JDK 17, Gradle 8.11.1,
  Android Gradle Plugin 8.9.1, and Kotlin 2.2.20.
- Keep generated build output and caches outside tracked source.
- Do not mix Phase 1 security implementation into this phase.

## Execution Notes

- The first Android JVM attempts failed before source compilation because the
  E-drive Gradle cache was missing
  `io.flutter:x86_64_debug:1.0.0-052f31d115eceda8cbff1b3481fcde4330c4ae12`
  and later `junit:junit:4.13.2`. The same artifacts were already available in
  the local C-drive Gradle cache.
- The existing Gradle `modules-2` and `transforms-3` caches were synchronized
  to `E:\Archive\Flutter\.note_secret_search_quality_cache\gradle`. The exact
  planned Gradle command then passed, followed by a successful debug APK build.
  No dependency versions or production behavior were changed for this
  environment repair.

## Tasks

### 1. Baseline and Worktree

- [x] Create or verify the clean `codex/repair-phase-0` worktree.
- [x] Relocate Gradle, Pub, temporary, and build caches to the E: drive.
- [x] Run `flutter pub get --enforce-lockfile`, `flutter analyze`,
  `flutter test`, Android JVM tests, and a debug APK build.
- [x] Record failures as reproducible environment or source failures.

### 2. Repository Ignore Rules

- [x] Remove malformed ignore patterns.
- [x] Stop ignoring Android XML, text resources, and LLM source files.
- [x] Ignore generated `android/.kotlin/` output.
- [x] Keep historical `docs/superpowers` documents hidden.
- [x] Allow only `2026-07-13-note-secret-search-v0-2-*.md` repair plans
  under `docs/superpowers/plans/`.
- [x] Verify `git check-ignore` and `rg --files` behavior.

### 3. SDK and Documentation Alignment

- [x] Set Dart constraint to `>=3.11.0 <4.0.0`.
- [x] Set Flutter constraint to `>=3.38.4`.
- [x] Document Flutter, Dart, Android SDK, target SDK, JDK, and Gradle
  requirements in `README.md`.
- [x] Document `scripts/quality/Invoke-QualityChecks.ps1` as the local
  quality entry point.
- [x] Verify dependency resolution does not change dependency versions or
  modify `pubspec.lock`.

### 4. Widget Test Stability

- [x] Add a shared `scrollUntilFound` helper based on
  `WidgetTester.scrollUntilVisible`.
- [x] Replace fixed viewport assumptions in the model-management tests.
- [x] Scope model-card activation controls before reading widget state.
- [x] Cover installed-unverified LLM, degraded embedding, ready catalog,
  active embedding chip, and degraded local LLM cases.
- [x] Run the focused model-management test and adjacent search presentation
  tests.

### 5. Local Quality Script

- [x] Add `scripts/quality/Invoke-QualityChecks.ps1`.
- [x] Set `GRADLE_USER_HOME`, `PUB_CACHE`, `TEMP`, and `TMP` under the
  E-drive quality cache.
- [x] Fail immediately when a native command exits non-zero.
- [x] Support `-SkipAndroid` and `-SkipBuild`.
- [x] Run dependency resolution, analysis, Dart tests, Android JVM tests,
  and debug APK build in that order.

### 6. GitHub Actions

- [x] Add `.github/workflows/quality.yml`.
- [x] Run Flutter analysis and Dart tests on Ubuntu with Java 17 and Flutter
  3.41.5 stable.
- [x] Run Android JVM tests with the Gradle wrapper.
- [x] Build a debug APK after the analysis and JVM-test jobs pass.
- [x] Enable concurrency cancellation for superseded runs.

### 7. Phase Gate

- [x] Run the complete local quality script.
- [x] Run `git diff --check`.
- [x] Verify source files are not accidentally ignored.
- [x] Verify future v0.2 child plans are trackable while historical plans
  remain ignored.
- [x] Confirm the worktree contains only scoped Phase 0 changes.
- [x] Commit the Phase 0 implementation on `codex/repair-phase-0`.

## Verification Commands

```powershell
.\scripts\quality\Invoke-QualityChecks.ps1
git diff --check
git status --short --branch
```

The Android JVM test and debug APK build must be run sequentially locally.
If dependency download is blocked by the environment, preserve the exact
failure and distinguish it from a source failure.

## Acceptance Criteria

- Main worktree changes remain untouched.
- Ignore parsing succeeds and source files remain visible to Git.
- SDK constraints, lockfile, README, and CI agree.
- Model-management tests do not depend on fixed scroll offsets.
- Local and CI quality commands cover the same checks.
- Flutter analysis and Dart tests pass.
- Android JVM tests and debug APK build pass, or have a documented,
  reproducible external dependency failure.
- No Phase 1 security code is included.
