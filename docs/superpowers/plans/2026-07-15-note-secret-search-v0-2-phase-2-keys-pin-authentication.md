# Phase 2: Keys, PIN, and Authentication Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Parent Plan:** `docs/2026-07-13-note-secret-search-v0-2-repair-roadmap.md`

**Goal:** Replace the legacy plaintext database password, plaintext PIN, pre-authentication database opening, and UTF-8 pseudo-ciphertext with authenticated Android key envelopes, persistent PIN protection, an explicit locked database lifecycle, and recoverable lossless migration.

**Architecture:** A native Android keyring owns the random master DEK and all system/PIN wrapping envelopes. It returns short-lived, domain-separated database and field keys only after successful authentication. Flutter owns a lease-gated SQLCipher lifecycle and session field-crypto key, while a journaled copy-and-swap migration rewrites business data into a schema-v4 pending database before deleting any legacy material.

**Tech Stack:** Flutter 3.41.5, Dart 3.11.3, Riverpod 2.6.1, SQLCipher, PointyCastle 4.0.0, Android Kotlin, Android Keystore, StrongBox, AndroidX Biometric, argon2kt 1.6.0, AtomicFile, MethodChannel, JUnit, Flutter tests, Android instrumentation.

---

## Task 1: Create the Phase-2 Worktree and Save the Plans

- [x] Create `codex/repair-phase-2` at Phase-1 commit `9c0b73c`.
- [x] Save this umbrella plan and the P2A-P2E child plans before production edits.
- [x] Verify the main worktree's unrelated edits are unchanged.
- [x] Run the Phase-1 baseline gate in the isolated worktree.
- [x] Commit with `docs: add phase 2 key and authentication plans`.

## Task 2: P2A - Build the Native Authenticated Keyring

- [x] Add failing JVM tests for fresh provisioning, existing envelopes, corrupt envelopes, missing aliases, StrongBox success/fallback, authentication cancellation, key invalidation, and atomic persistence failure.
- [x] Generate one random 32-byte master DEK and derive `K_db` and `K_field` with HKDF-SHA256 and fixed domain labels.
- [x] Store only versioned AES-256-GCM envelopes in `noBackupFilesDir/security/keyset-v2.json` through `AtomicFile`.
- [x] On API 30+, use an authentication-per-use key supporting strong biometric or device credential.
- [x] On API 24-29, maintain a device-credential envelope and an optional authentication-per-use biometric envelope.
- [x] Request StrongBox on API 28+ and retry ordinary Android Keystore only for explicit unsupported/unavailable failures.
- [x] Report the actual `strongBox`, `tee`, `software`, or `unknown` security level without making a hardware claim when unknown.
- [x] Replace boolean biometric authentication with typed system-auth results and make `onAuthenticationFailed` non-terminal.
- [x] Add typed MethodChannel state/provision/unlock/lock and migration operations.
- [x] Run JVM and bridge tests, then commit with `feat: add authenticated native security keyring`.

## Task 3: P2B - Add PIN Envelopes and Authenticated Field Encryption

- [x] Add failing JVM tests for Argon2id parameters, PIN envelope tampering, wrong PIN, persistent throttling, restart/reboot handling, PIN replacement, and PIN removal.
- [x] Derive the PIN KEK with Argon2id using 65536 KiB, 3 iterations, parallelism 1, a 16-byte salt, and 32-byte output.
- [x] Wrap the master DEK with AES-256-GCM using a 12-byte nonce, 16-byte tag, and KDF-bound AAD.
- [x] Persist five-failure/60-second throttling using monotonic time, wall time, and boot count; reset only after successful PIN unlock.
- [x] Add failing Dart tests for field-envelope round trips, tampering, row/column substitution, null/empty preservation, invalid legacy bytes, and key zeroization.
- [x] Replace `MvpCryptoService` with a session-bound AES-256-GCM implementation using the binary `NSSF` envelope.
- [x] Bind field AAD to length-prefixed table, row ID, and column identifiers.
- [x] Convert all nine pseudo-ciphertext columns to contextual encryption calls and make normal repositories reject legacy UTF-8 bytes.
- [x] Remove PIN material and verification from `SharedPreferencesSecuritySettingsRepository`.
- [x] Run focused native, crypto, secret, note, provider, and search tests, then commit with `feat: add pin envelopes and authenticated field encryption`.

## Task 4: P2C - Gate the Database Lifecycle Behind Authentication

- [x] Add failing tests for every database transition, illegal transition, lock during open, lock during query/transaction, stale result publication, close timeout, close failure, and retry from error.
- [x] Replace the raw database getter with `state`, `states`, `open(sessionKeys)`, `run(operation)`, and `close()`.
- [x] Permit repository operations only in `open`; each operation holds a generation-bound lease for its full query or transaction.
- [x] Make `close()` enter `closing` synchronously, revoke new leases, wait up to five seconds, close SQLCipher, and reject stale results.
- [x] Move schema creation and default-vault creation into the database open path and remove duplicate bootstrap schema execution.
- [x] Convert all eight SQLite repositories to `run()`.
- [x] Make bootstrap load only security/recovery state and never request database key material.
- [x] Fix unlock ordering: authenticate and unwrap, open or migrate, recheck lock epoch/foreground, remove shield, then mark unlocked.
- [x] Fix lock ordering: enable shield, revoke database access, mark locked and purge providers, close SQLCipher, then clear session keys.
- [x] Derive sensitive access from both unlocked session and `DatabaseLifecycleStatus.open`.
- [x] Add fresh-provisioning, opening, migration, recovery, and sanitized error lock-screen states.
- [x] Run focused lifecycle/auth/repository tests, then commit with `fix: gate database lifecycle behind authentication`.

## Task 5: P2D - Migrate Legacy Security Data Safely

- [x] Add failing migration tests for fresh install, v1, v2, upgraded-v3, fresh-v3, missing/blank legacy password, inconsistent PIN state, insufficient space, every interruption stage, repeated execution, corrupt pending data, and rollback.
- [x] Add schema v4 security metadata without pulling Phase-3 constraints, indexes, or ownership refactors forward.
- [x] Require free space of at least twice the source database file set plus 64 MiB before mutation.
- [x] Checkpoint and close the source database, reject any remaining WAL/SHM sidecars, then copy the encrypted main database into an app-private no-backup workspace and record its SHA-256 digest.
- [x] Create a `K_db`-encrypted pending database and copy preserved tables in one target transaction.
- [x] Re-encrypt the nine legacy fields byte-for-byte with contextual field envelopes.
- [x] Preserve vaults, all password/note rows, tags, item tags, categories, provider/sync configs, app settings, chat history, and model registry.
- [x] Discard and rebuild embedding chunks, download tasks, and model catalog rows.
- [x] Validate schema, primary keys, row counts, canonical non-secret hashes, every transformed plaintext, envelope authentication, and provider JSON.
- [x] Implement the durable stages `detected`, `keyringReady`, `backupReady`, `pendingCreated`, `rowsCopied`, `validated`, `oldMoved`, `newActivated`, `postSwapValidated`, and `cleanupComplete`.
- [x] Use a native file coordinator for path validation, fsync, atomic activation, rollback, and cleanup.
- [x] Delete rollback and backup files before deleting the legacy database password and plaintext PIN; delete the journal last.
- [x] Run focused migration and recovery tests, then commit with `feat: migrate legacy security data safely`.

## Task 6: P2E - Complete Recovery Paths and the Phase Gate

- [x] Recover a valid master DEK through PIN when system envelopes are invalidated, then rebind system authentication.
- [x] Require PIN replacement when only the PIN envelope is corrupt.
- [x] Preserve all databases and backups and enter `recoveryRequired` when no envelope can unwrap the master DEK.
- [x] Run complete JVM, Dart, migration-fixture, and static sensitive-material tests.
- [x] Run debug APK and instrumentation tests on the Huawei `SPN-AL00`.
- [x] Exercise fresh install, upgrade, system credential, PIN, relock, process restart cooldown, interrupted migration, rollback, and Logcat sentinel checks.
- [x] Request independent specification and code-quality reviews and resolve every Phase-2 finding.
- [x] Run `git diff --check` and verify the worktree is clean.
- [x] Commit with `test: complete phase 2 security gate`.

## Acceptance Criteria

- No plaintext database password, plaintext PIN, fixed fallback, or unauthenticated key retrieval remains.
- SQLCipher never opens before successful provisioning or unlock.
- Repositories cannot access SQLCipher unless its lifecycle state is `open`.
- Locking obscures the UI, revokes repository access, closes SQLCipher, and clears controllable key material.
- System and PIN envelopes cannot be substituted, replayed across key IDs, or silently regenerated after loss.
- All nine pseudo-ciphertext columns contain authenticated versioned envelopes.
- Existing passwords and notes survive v1/v2/v3 migration and every tested interruption.
- Legacy material is deleted only after post-swap validation.
- The main worktree remains untouched and no Phase-3 work is mixed into this branch.

## Assumptions

- Fresh provisioning requires a configured secure device credential; app PIN is an optional post-unlock fallback.
- Chat bodies, titles, tags, categories, and vault metadata remain protected by SQLCipher only in this phase.
- The SQLCipher plugin requires one short-lived immutable password string during open; the database is closed on lock to release the native connection object.
- API 24/28/30 branches receive JVM adapter coverage; the Phase-2 real-device gate uses the connected API-29 Huawei device.
