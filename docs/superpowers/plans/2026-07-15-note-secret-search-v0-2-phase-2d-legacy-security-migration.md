# Phase 2D: Legacy Security Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` and execute every checkbox in order.

**Parent Plan:** `docs/superpowers/plans/2026-07-15-note-secret-search-v0-2-phase-2-keys-pin-authentication.md`

**Goal:** Move legacy v1-v3 databases and plaintext security material into schema v4 without losing passwords or notes and with deterministic interruption recovery.

**Architecture:** Migration never rekeys the active database in place. It creates an encrypted backup, writes a new pending database with transformed fields, validates it fully, and atomically activates it through a native file coordinator.

---

## Files

- Add `lib/core/storage/migration/` inventory, journal, copier, validator, and orchestrator modules.
- Add native `MigrationFileCoordinator` and MethodChannel operations.
- Add schema-v4 security metadata and migration fixture builders/tests.
- Modify bootstrap/security state handling to resume or roll back before normal unlock.

## Tasks

- [ ] Build source fixtures for v1, v2, upgraded-v3, fresh-v3, soft-deleted records, provider secrets, app settings, sync configs, and chat history.
- [ ] Add failure-injection tests for every journal stage, free-space rejection, invalid UTF-8, corrupt pending envelopes, wrong legacy password, and repeat execution.
- [ ] Verify the fixture/recovery tests fail before implementation.
- [ ] Implement strict source inventory and classify fresh, legacy, migrated, interrupted, and unrecoverable states without mutation.
- [ ] Implement an AtomicFile journal containing no secrets and validate journal claims against actual file hashes and identities.
- [ ] Implement native path confinement, fsync, encrypted file-set backup, atomic rename, restore, and cleanup.
- [ ] Require free space of `2 * source file-set bytes + 64 MiB`.
- [ ] Checkpoint and close the source database before copying the main/WAL/SHM set.
- [ ] Create schema-v4 pending storage using `K_db` and a key-ID/security-metadata marker.
- [ ] Copy preserved tables in one target transaction and transform all nine pseudo-ciphertext fields with exact contextual AAD.
- [ ] Leave embedding chunks, download tasks, and catalog rows empty for later rebuild.
- [ ] Validate table/PK counts, canonical non-secret hashes, all transformed plaintext, envelope tags, provider JSON, and SQL quick-check results.
- [ ] Implement forward completion and rollback for every durable stage.
- [ ] Post-activate, reopen with `K_db`, repeat critical validation, then delete rollback/backup, legacy native password, plaintext PIN, and journal in that order.
- [ ] Run fixture, recovery, focused repository, and Android file-coordinator tests.
- [ ] Commit with `feat: migrate legacy security data safely`.

## Gate

- No source file or legacy preference is changed before backup completion.
- A failed or killed migration always leaves either a valid legacy database or a validated schema-v4 database.
- Every password/note/provider plaintext matches exactly after migration.
- Cleanup is idempotent and never runs before post-swap validation.
