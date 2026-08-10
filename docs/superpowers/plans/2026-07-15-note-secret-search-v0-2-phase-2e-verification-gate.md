# Phase 2E: Recovery and Verification Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:verification-before-completion` and request independent reviews before completion.

**Parent Plan:** `docs/superpowers/plans/2026-07-15-note-secret-search-v0-2-phase-2-keys-pin-authentication.md`

**Goal:** Prove that every provisioning, unlock, lock, migration, invalidation, rollback, and recovery path preserves the authentication boundary and business data.

**Architecture:** Focused automated suites run before the full gate. Native instrumentation and host-side Logcat checks verify behavior that JVM and Dart fakes cannot establish.

---

## Tasks

- [x] Add recovery tests for system-envelope invalidation with valid PIN, corrupt PIN with valid system auth, and loss of every envelope.
- [x] Implement system rebind after PIN recovery without replacing the master DEK.
- [x] Require PIN replacement after PIN-envelope corruption and preserve all database files when recovery is unavailable.
- [x] Run focused auth, keyring, PIN, field crypto, lifecycle, repository, and migration tests.
- [x] Run `flutter analyze`.
- [x] Run the complete Dart test suite.
- [x] Run `.\gradlew.bat :app:testDebugUnitTest --no-daemon`.
- [x] Run `flutter build apk --debug`.
- [x] Run instrumentation on Huawei `SPN-AL00` for fresh provisioning, system unlock, PIN unlock, relock, key invalidation, process restart cooldown, upgrade, interruption, and rollback.
- [x] Run the sensitive Logcat sentinel scan and static scans for legacy key/PIN storage, unauthenticated database open, pseudo-ciphertext, and sensitive errors.
- [x] Request an independent specification review and an independent code-quality/security review.
- [x] Resolve every Critical, Important, and Minor Phase-2 finding with a failing regression test.
- [x] Re-run the complete gate, `git diff --check`, and verify a clean worktree.
- [x] Commit with `test: complete phase 2 security gate`.

## Verification Evidence - 2026-07-18

- `flutter analyze`: no issues.
- Complete Dart suite: 590 tests passed.
- Android JVM suite: `:app:testDebugUnitTest` passed.
- Debug APK: `flutter build apk --debug` passed.
- Huawei `SPN-AL00`, Android API 29: 14 instrumentation tests passed with 0 skipped and 0 failed.
- The local-runtime smoke test loaded and generated with the official `SmolLM2-360M-Instruct` Q8_0 GGUF after verifying SHA-256 `48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201`.
- Logcat contained zero matches for the model-path, prompt, and migration-path sentinels.
- Independent specification and standards/security reviews reported no remaining Phase-2 findings.
- API 24 and current-target real-device coverage remains a Phase-9 device-matrix gate; API 24/28/30 behavior is covered here through JVM adapters and the API-29 device gate.

## Completion Statement

Phase 2 is complete only when cold start, relock, system credential, biometric, PIN, migration, rollback, and recovery all require successful DEK unwrapping; every existing password and note is preserved; and no legacy plaintext security material remains.
