# Phase 2C: Authenticated Database Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` and execute every checkbox in order.

**Parent Plan:** `docs/superpowers/plans/2026-07-15-note-secret-search-v0-2-phase-2-keys-pin-authentication.md`

**Goal:** Ensure SQLCipher is opened only after authentication and is inaccessible and closed whenever the application locks.

**Architecture:** `AppDatabase` becomes a lease-gated lifecycle module. `SecurityOrchestrator` serializes authentication, database opening, shield removal, session publication, and the reverse lock sequence.

---

## Files

- Replace `lib/core/storage/database/app_database.dart` and refactor `sqlcipher_database.dart`.
- Add database lifecycle/session-key tests under `test/core/storage/database/`.
- Modify bootstrap, security orchestration, lifecycle guard, lock UI, and Riverpod composition.
- Convert all eight SQLite repository adapters from `.database` to `run()`.

## Tasks

- [ ] Add tests for legal/illegal state transitions, open cancellation, open failure, lock during open, active leases, stale results, close timeout/failure, and retry.
- [ ] Verify lifecycle tests fail against the current lazy-open interface.
- [ ] Define `DatabaseLifecycleStatus`, `DatabaseLifecycleState`, sanitized stages/errors, and access-revoked exceptions.
- [ ] Implement generation-bound `open`, `run`, and `close`; set `closing` before the first await and reject all new leases.
- [ ] Scope the immutable SQLCipher password string to the `openDatabase` call and clear mutable key bytes immediately afterward.
- [ ] Move schema creation, upgrades, and default-vault creation into the open transaction.
- [ ] Convert vault, secret, note, embedding, chat, model registry, model download, and provider repositories to `run()`.
- [ ] Add repository tests proving direct operations fail while locked/closing/error.
- [ ] Make bootstrap enable screenshot protection and load native security state without opening SQLCipher.
- [ ] Rework system/PIN unlock to open the database before removing the shield or publishing an unlocked session.
- [ ] Rework every lock path to shield, revoke database access, lock/purge state, close SQLCipher, and clear native/Dart session keys.
- [ ] Add background timeout scheduling so an elapsed timeout closes the database before resume.
- [ ] Derive sensitive access from both unlocked session and open database state.
- [ ] Add unprovisioned, opening, recovery-required, and sanitized-error lock UI states.
- [ ] Run focused auth, lifecycle, repository, routing, and provider tests.
- [ ] Commit with `fix: gate database lifecycle behind authentication`.

## Gate

- Cold bootstrap performs no database-password request and no SQLCipher open.
- An unlocked session is never visible while the database is not open.
- Lock immediately prevents new repository calls and eventually closes the connection.
- No stale operation result reaches a provider after the lock generation changes.
