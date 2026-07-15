# Phase 2E: Recovery and Verification Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:verification-before-completion` and request independent reviews before completion.

**Parent Plan:** `docs/superpowers/plans/2026-07-15-note-secret-search-v0-2-phase-2-keys-pin-authentication.md`

**Goal:** Prove that every provisioning, unlock, lock, migration, invalidation, rollback, and recovery path preserves the authentication boundary and business data.

**Architecture:** Focused automated suites run before the full gate. Native instrumentation and host-side Logcat checks verify behavior that JVM and Dart fakes cannot establish.

---

## Tasks

- [ ] Add recovery tests for system-envelope invalidation with valid PIN, corrupt PIN with valid system auth, and loss of every envelope.
- [ ] Implement system rebind after PIN recovery without replacing the master DEK.
- [ ] Require PIN replacement after PIN-envelope corruption and preserve all database files when recovery is unavailable.
- [ ] Run focused auth, keyring, PIN, field crypto, lifecycle, repository, and migration tests.
- [ ] Run `flutter analyze`.
- [ ] Run the complete Dart test suite.
- [ ] Run `.\gradlew.bat :app:testDebugUnitTest --no-daemon`.
- [ ] Run `flutter build apk --debug`.
- [ ] Run instrumentation on Huawei `SPN-AL00` for fresh provisioning, system unlock, PIN unlock, relock, key invalidation, process restart cooldown, upgrade, interruption, and rollback.
- [ ] Run the sensitive Logcat sentinel scan and static scans for legacy key/PIN storage, unauthenticated database open, pseudo-ciphertext, and sensitive errors.
- [ ] Request an independent specification review and an independent code-quality/security review.
- [ ] Resolve every Critical, Important, and Minor Phase-2 finding with a failing regression test.
- [ ] Re-run the complete gate, `git diff --check`, and verify a clean worktree.
- [ ] Commit with `test: complete phase 2 security gate`.

## Completion Statement

Phase 2 is complete only when cold start, relock, system credential, biometric, PIN, migration, rollback, and recovery all require successful DEK unwrapping; every existing password and note is preserved; and no legacy plaintext security material remains.
