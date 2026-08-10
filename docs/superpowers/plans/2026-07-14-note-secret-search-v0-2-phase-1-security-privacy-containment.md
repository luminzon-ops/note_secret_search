# Phase 1: Security and Privacy Containment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Parent Plan:** `docs/2026-07-13-note-secret-search-v0-2-repair-roadmap.md`

**Goal:** Remove every known fixed-key fallback, locked-route bypass, automatic external-data path, sensitive plaintext log, unavailable multimodal entry, and unverified trust claim while preserving the local LLM as a core capability.

**Architecture:** Keep Phase 1 as containment rather than a full authentication or native-runtime rewrite. Security failures remain closed, locked navigation is guarded both by router redirects and the lock overlay, Riverpod plaintext is invalidated on lock, external AI requires an explicit per-session selection plus configuration-bound consent, and the local GGUF runtime bypasses the logging AAR helper through an app-owned file-descriptor adapter.

**Tech Stack:** Flutter 3.41.5, Dart 3.11.3, Riverpod 2.6.1, go_router 14.8.1, Android Kotlin, SharedPreferences, MethodChannel, llama.cpp AAR, JUnit, Android instrumentation, PowerShell, Flutter widget tests.

---

## Task 1: Save the Plan and Preserve the Baseline

- [ ] Add the parent roadmap and this child plan to the Phase 1 worktree.
- [ ] Verify the main worktree still contains the user's original unrelated changes.
- [ ] Commit with `docs: add phase 1 security containment plan`.

## Task 2: Make Legacy Database Key Access Fail Closed

- [ ] Add Kotlin tests for fresh initialization, existing valid material, initialized-but-missing material, blank material, and failed persistence.
- [ ] Add Dart tests proving null or blank MethodChannel material and blank gateway material throw before database initialization.
- [ ] Refactor `SecureKeyManager` behind a testable preference store and atomically persist the initialization marker with random material.
- [ ] Map native key failures to `SECURE_KEY_UNAVAILABLE` without returning exception details.
- [ ] Remove password-material logging from `SecurityOrchestrator`.
- [ ] Run focused Kotlin and Dart tests, then commit with `fix: fail closed when database key material is unavailable`.

## Task 3: Enforce Locked Routing and Lifecycle Shielding

- [ ] Replace tests that currently expect locked PIN setup access with tests that expect the lock screen and router redirect.
- [ ] Add router tests for every protected route, invalid PIN unlock, and unlocked-only PIN settings.
- [ ] Add lifecycle tests for immediate lock, timeout lock, resume without timeout, concurrent transitions, settings failure, and shield failure.
- [ ] Remove `/unlock/pin/setup`, remove the lock-screen PIN setup action, and permit `/unlock/pin` only when PIN material is ready.
- [ ] Add a router refresh notifier driven by lock and PIN state.
- [ ] Serialize lifecycle transitions and remove the recent-task shield only after a successful unlock decision.
- [ ] Make biometric and PIN unlock keep the session locked when unshielding fails.
- [ ] Run focused auth tests, then commit with `fix: enforce locked routing and lifecycle shielding`.

## Task 4: Clear Sensitive Riverpod State on Lock

- [ ] Add tests that populate search, chat, manual context, session selection, provider configuration, and model runtime state.
- [ ] Add `SensitiveStateInvalidator` and invalidate secret/note details, search results, chats, external configuration, and model path state.
- [ ] Add `resetForLock()` to chat controllers and reset private context, manual items, backend selection, messages, and session restoration.
- [ ] Listen to lock transitions in the root app and clear state immediately when locked.
- [ ] Run focused provider tests, then commit with `fix: clear sensitive application state on lock`.

## Task 5: Require Explicit External AI Consent

- [ ] Change the automatic-fallback test to require local failure with zero external calls.
- [ ] Add tests for explicit external selection, missing consent, cancelled consent, configuration changes, and private-context policy.
- [ ] Add `ChatBackendPreference` to requests and conversation state with `local` as the default.
- [ ] Resolve exactly the selected backend and never fall through to another backend.
- [ ] Hash provider type, normalized endpoint, model, and sensitive-field policy into the consent preference key.
- [ ] Revoke prior consent when provider configuration is saved.
- [ ] Add a Local/External segmented selector and show provider type, endpoint, model, and context classification before consent.
- [ ] Ignore manual context whenever private context is disabled.
- [ ] Run chat/provider tests, then commit with `fix: require explicit consent for external AI requests`.

## Task 6: Remove Sensitive Logs While Preserving Local LLM

- [ ] Add source-policy tests for fixed fallback text, prompt values, key state, private content, absolute model/database paths, and raw exception logging.
- [ ] Add Kotlin tests for sanitized runtime errors and file-descriptor load parameters.
- [ ] Remove sensitive Dart and Kotlin logs and make `AppLogger.error` record only event text and exception type.
- [ ] Move the AAR-facing client into an app-owned adapter that constructs `LlamaContext` with a file descriptor and a fixed logical model name.
- [ ] Keep real local load, generation, cancellation, and release behavior.
- [ ] Add Android instrumentation plus a host Logcat smoke script using path and prompt sentinels.
- [ ] Run source, JVM, and device checks, then commit with `fix: remove sensitive runtime logging`.

## Task 7: Hide Unavailable and Unverified Model Capabilities

- [ ] Change catalog and widget tests to assert multimodal entries are absent.
- [ ] Change plugin tests to expect `UNSUPPORTED_CAPABILITY` before multimodal arguments are read.
- [ ] Change formatter tests to assert signature metadata never produces a trust badge.
- [ ] Filter multimodal catalog and installed entries in both repository and UI layers.
- [ ] Reject multimodal download/runtime activation and remove placeholder signature fields from the built-in catalog.
- [ ] Remove all "signed" status formatting while preserving checksums.
- [ ] Run model tests, then commit with `fix: hide unavailable and unverified model capabilities`.

## Task 8: Execute the Phase 1 Gate

- [ ] Run all focused auth, chat, provider, model, and logging-policy tests.
- [ ] Run `flutter analyze`, the complete Dart suite, Android JVM tests, and a debug APK build.
- [ ] Run instrumentation and the Logcat sentinel smoke check on the connected Huawei device.
- [ ] Scan for fixed fallback text, locked PIN setup routes, automatic external fallback, sensitive log templates, multimodal exposure, and false signature claims.
- [ ] Run `git diff --check` and verify the Phase 1 worktree is clean.

## Acceptance Criteria

- No fixed database key or silent key regeneration remains.
- Locked users cannot reach PIN setup or protected routes.
- Sensitive content stays obscured until unlock succeeds.
- Locking clears cached plaintext and session privacy choices.
- Local failure never causes an external request.
- External requests require explicit selection and configuration-bound consent.
- Local LLM remains available without app-owned or helper-level path/prompt logging.
- Multimodal functionality and unverified signature status are not exposed.
- The main worktree remains untouched.
