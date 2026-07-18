# Phase 2B: PIN Envelopes and Field Encryption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` and execute every checkbox in order.

**Parent Plan:** `docs/superpowers/plans/2026-07-15-note-secret-search-v0-2-phase-2-keys-pin-authentication.md`

**Goal:** Add native Argon2id PIN wrapping and replace UTF-8 pseudo-ciphertext with session-bound authenticated field envelopes.

**Architecture:** Native code owns PIN derivation, DEK wrapping, and throttling. Dart receives only derived session keys and uses a contextual synchronous AES-GCM module for encrypted database fields.

---

## Files

- Create native PIN derivation, envelope, and throttle modules in the Phase-2 security package.
- Create `lib/core/security/database_session_keys.dart`, `field_crypto.dart`, and `field_envelope.dart`.
- Modify the crypto provider, secret/note mappers, provider repository, and every decrypting search/presentation caller.
- Remove PIN-material methods from the SharedPreferences settings repository.

## Tasks

- [x] Pin `com.lambdapioneer.argon2kt:argon2kt:1.6.0` and `pointycastle: 4.0.0`.
- [x] Add JVM tests for exact Argon2id parameters, wrong PIN, envelope tampering, PIN replacement/removal, threshold behavior, process restart, reboot, and clock rollback.
- [x] Verify the native tests fail before implementation.
- [x] Implement native PIN KEK derivation on a controlled worker and clear mutable PIN, KEK, and DEK buffers in `finally`.
- [x] Implement persistent five-failure/60-second throttling using elapsed time, boot count, and wall time.
- [x] Extend the native channel with `unlockWithPin`, `configurePin`, and `removePin`.
- [x] Add Dart tests defining the `NSSF` binary layout, contextual AAD, tamper rejection, null/empty semantics, and zeroization.
- [x] Verify the Dart tests fail before implementation.
- [x] Implement `DatabaseSessionKeys` with idempotent `clear()` and separate database/field key ownership.
- [x] Implement field AES-256-GCM with 12-byte random nonces, 16-byte tags, strict parsing, and no whitespace trimming.
- [x] Change the crypto interface to require table, row ID, and column context.
- [x] Convert secret, note, provider, sync-account, and app-setting field paths; add migration-only legacy UTF-8 decoding.
- [x] Remove plaintext PIN save/verify/has methods from SharedPreferences and make native state authoritative.
- [x] Run focused native, crypto, secret, note, provider, search, and widget tests.
- [x] Commit with `feat: add pin envelopes and authenticated field encryption`.

## Gate

- PIN material is absent from SharedPreferences after fresh configuration.
- Normal field decryption rejects raw UTF-8 legacy bytes and wrong row/column contexts.
- Successful PIN unlock resets persisted failures; process restart does not.
- Session field-key bytes are overwritten on lock/dispose.
