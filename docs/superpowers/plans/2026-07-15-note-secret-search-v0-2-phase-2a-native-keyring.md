# Phase 2A: Native Authenticated Keyring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:test-driven-development` and execute every checkbox in order.

**Parent Plan:** `docs/superpowers/plans/2026-07-15-note-secret-search-v0-2-phase-2-keys-pin-authentication.md`

**Goal:** Replace plaintext native database-password storage with a versioned, authentication-bound Android Keystore envelope around one random master DEK.

**Architecture:** `SecureKeyManager` becomes the small external interface over internal Keystore, envelope-store, authenticator, and key-derivation adapters. JVM tests use fakes; instrumentation verifies the real Android Keystore and prompt lifecycle.

---

## Files

- Create Kotlin modules under `android/app/src/main/kotlin/com/example/note_secret_search/security/`.
- Modify `NativeSecurityPlugin.kt`, `BiometricAuthenticator.kt`, and `android/app/build.gradle.kts`.
- Modify Dart bridge and security-domain types under `lib/features/auth_security/`.
- Add matching JVM, Dart bridge, and instrumentation tests.

## Tasks

- [x] Add JVM tests defining keyset parsing, AES-GCM envelope AAD, HKDF vectors, StrongBox fallback, alias loss, corruption, and atomic write failure.
- [x] Run `.\gradlew.bat :app:testDebugUnitTest --tests "*SecurityKey*" --no-daemon` and confirm the new tests fail because the modules do not exist.
- [x] Implement typed key IDs, envelope metadata, security levels, and sanitized native error codes.
- [x] Implement `AtomicFileSecurityEnvelopeStore` in `noBackupFilesDir/security/keyset-v2.json`; validate every field and reject unknown algorithms or malformed lengths.
- [x] Implement Android Keystore AES-256-GCM key generation with StrongBox request on API 28+ and a narrowly scoped fallback.
- [x] Implement API-30+ combined authentication-per-use unwrap and API-24-29 device-credential plus optional biometric envelopes.
- [x] Implement master-DEK generation and HKDF labels `note-secret-search/sqlcipher/v1` and `note-secret-search/field/v1`.
- [x] Add `getSecurityState`, `provisionWithSystemAuth`, `unlockWithSystemAuth`, and `lock` MethodChannel handlers.
- [x] Make repeated biometric mismatch callbacks non-terminal; map cancellation, lockout, missing credential, invalidation, and storage failures to stable codes.
- [x] Add Dart types `NativeSecurityState`, `NativeUnlockResult`, `KeySecurityLevel`, and `NativeSecurityException`; reject malformed channel payloads.
- [x] Run focused JVM and Dart bridge tests.
- [x] Run existing Phase-1 native security and sensitive-log policy tests.
- [x] Commit with `feat: add authenticated native security keyring`.

## Gate

- No new keyset contains plaintext DEK or SQLCipher password.
- Existing legacy preferences are only detected, never deleted or overwritten.
- An existing envelope with a missing alias reports recovery rather than provisioning a new DEK.
- StrongBox fallback is observable and never represented as StrongBox success.
