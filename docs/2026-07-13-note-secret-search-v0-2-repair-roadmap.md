# Note Secret Search v0.2 Repair Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:writing-plans` to create one detailed child plan per phase, then use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement that child plan task-by-task. Child plans must use checkbox (`- [ ]`) steps for tracking.

**Parent Plan Path:** `docs/2026-07-13-note-secret-search-v0-2-repair-roadmap.md`

**Goal:** Repair the current Android-first MVP into a publishable `v0.2.0` with trustworthy security boundaries, lossless migration of existing business data, correct search and local AI behavior, and reproducible builds and tests.

**Architecture:** Preserve the Flutter feature-first structure and domain ports while rebuilding the security, persistence, search, and native runtime boundaries in dependency order. Each phase is planned and implemented independently in a `codex/repair-*` worktree, uses TDD and small commits, and must pass its gate before the next phase begins.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, SQLCipher, Android Kotlin, Android Keystore, MethodChannel, ONNX Runtime, llama.cpp/GGUF, Dio, SharedPreferences, Flutter tests, JUnit, Android instrumentation tests, GitHub Actions.

---

## Roadmap Authority

This document is the parent plan for all `v0.2.0` repair work.

- Every phase must receive a separate detailed implementation plan under `docs/superpowers/plans/`.
- Child plans must link back to this roadmap and may refine implementation details without changing phase order, security assumptions, data-preservation requirements, or release gates.
- Any proposed scope change that weakens a gate or changes an assumption must update this roadmap first.
- P0 containment work may be pulled forward, but no phase may be declared complete until its full gate passes.
- No public release is allowed between security containment and completion of the security/data migration phases.

## Repair Phases

### Phase 0: Restore a Trustworthy Engineering Baseline

- [ ] Free or relocate Gradle and Pub caches so the system drive has at least 15 GB available.
- [ ] Fix invalid `.gitignore` patterns and prevent broad rules from hiding Android XML, text resources, or LLM source files.
- [ ] Align `pubspec.yaml`, `pubspec.lock`, README requirements, Flutter, Dart, JDK, Gradle, AGP, and Kotlin versions.
- [ ] Replace fixed-scroll widget tests with semantic finders and `scrollUntilVisible` behavior.
- [ ] Establish a clean-`HEAD` baseline for `flutter analyze`, all Dart tests, Android JVM tests, and debug APK builds.
- [ ] Add CI for analysis, Dart tests, Android JVM tests, and debug builds.

**Gate:** The worktree is clean, all existing tests pass, and the same CI commands pass repeatedly from a clean checkout.

### Phase 1: Emergency Security and Privacy Containment

- [ ] Remove the fixed database-password fallback and make key/runtime failures fail closed.
- [ ] Block PIN setup and all protected routes while the application is locked.
- [ ] Obscure sensitive content before background/resume checks and invalidate sensitive Riverpod state on lock.
- [ ] Disable automatic external-provider fallback unless the user has explicitly enabled external access.
- [ ] Prevent all private context from leaving the device before a valid provider-specific confirmation.
- [ ] Remove prompt, key material, private content, and sensitive file paths from Dart, Kotlin, AAR, and native logs.
- [ ] Hide unavailable multimodal functionality and unverified signature claims.

**Gate:** No fixed key, plaintext sensitive log, lock-screen bypass, or default external-data path remains.

### Phase 2: Rebuild Keys, PIN, and Authentication

- [ ] Use Android Keystore AES-256-GCM to protect the root wrapping key, preferring StrongBox when available and degrading safely when unavailable.
- [ ] Generate a random database DEK and store versioned biometric/device-credential and PIN-wrapped envelopes.
- [ ] Derive the PIN KEK with Argon2id using 64 MiB memory, 3 iterations, and parallelism 1; persist failure/cooldown state so process restart cannot reset throttling.
- [ ] Authenticate before opening SQLCipher and close the database when the application locks.
- [ ] Replace UTF-8 pseudo-ciphertext with versioned authenticated-encryption envelopes containing version, nonce, ciphertext, and authentication tag.
- [ ] Migrate the legacy database password, plaintext PIN, provider credentials, secret fields, and note fields without losing passwords or notes.
- [ ] Create an app-private encrypted migration backup, verify migrated data, and delete legacy material only after a successful commit.

**Gate:** Cold start, relock, biometric, device credential, PIN, upgrade, rollback, and recovery cannot bypass DEK unwrapping.

### Phase 3: Repair Database and Data Lifecycles

- [ ] Add versioned, idempotent, recoverable migrations and restore historically missing columns such as `model_registry.integrity_status`.
- [ ] Add required foreign keys, uniqueness constraints, and indexes for production query paths.
- [ ] Make soft deletion, tag cleanup, embedding cleanup, and multi-artifact cleanup transactional.
- [ ] Remove duplicate bootstrap schema execution and define one owner for database initialization and migrations.
- [ ] Move Vault ownership out of the Secrets feature and remove duplicated repository responsibilities.
- [ ] Replace per-item tag loading with joined or batched queries.

**Gate:** Fresh install and v1, v2, and v3 fixture upgrades preserve business data, tolerate interruption, and resume or roll back safely.

### Phase 4: Rebuild Search Index Correctness

- [ ] Add explicit source-field identity, HMAC-SHA256 content fingerprint, index configuration version, and chunk schema version to `EmbeddingChunk`.
- [ ] Generate chunks per field instead of inferring fields from chunk positions.
- [ ] Apply the same scope policy to keyword search, indexing, semantic search, and AI context retrieval.
- [ ] Transactionally replace every source/model chunk set during rebuild and purge stale chunks after deletion or configuration changes.
- [ ] Replace JSON vector storage with compact float32 blobs.
- [ ] Preserve the existing fusion intent while calculating weights, thresholds, explanations, and observability from real field metadata.

**Gate:** Production index-to-search integration tests verify field attribution, scope enforcement, stale-data removal, ranking, and explanations.

### Phase 5: Repair the Android Embedding Runtime

- [ ] Read actual values from `OnnxTensor`/`OnnxValue` outputs before pooling and normalization.
- [ ] Implement the BERT normalizer, Chinese-character handling, pre-tokenization, and WordPiece behavior required by the catalog tokenizer metadata.
- [ ] Move model loading, tokenizer parsing, and inference off the Android platform thread onto a controlled worker.
- [ ] Key session caches by model ID, path, checksum, tokenizer spec, and runtime spec.
- [ ] Release ORT sessions when the engine/activity is destroyed and before model replacement or deletion.
- [ ] Add Chinese golden-corpus, real ONNX inference, repeated-load, model-switch, cancellation, and long-running indexing coverage.

**Gate:** Golden tests and real Android inference return valid vectors without UI-thread blocking or stale sessions.

### Phase 6: Repair LLM, Chat, and External Privacy Boundaries

- [ ] Replace the opaque patched AAR with a reproducible, pinned, auditable llama.cpp/AAR build that does not log prompts.
- [ ] Serialize model load, generation, cancellation, and release through one lifecycle coordinator.
- [ ] Bind external-provider confirmation to provider type, endpoint, model, and configuration fingerprint, with an explicit revoke path.
- [ ] Make external AI opt-in only; local failure must never silently resend a request externally.
- [ ] Include bounded conversation history while always preserving the current user question during prompt truncation.
- [ ] Send actual permitted manual context rather than titles only; password fields are excluded from all external prompts by default.
- [ ] Reset private-context toggles and manual selections when starting a new session.
- [ ] Preserve original session creation time and store the actual backend/model used for each response.

**Gate:** Privacy-matrix, prompt-budget, session-restore, provider-change, cancellation, and native concurrency tests pass.

### Phase 7: Repair Model Download, Trust, and Device Capability

- [ ] Sign a canonical catalog manifest and verify it with an embedded public key.
- [ ] Require an independent checksum for every required artifact.
- [ ] Represent multi-file models with structured artifact manifests across catalog, registry, download, repair, and deletion flows.
- [ ] Release active native sessions before replacing or deleting artifacts.
- [ ] Connect Device Profiler results to compatibility guidance and default recommendations without bypassing runtime validation.
- [ ] Keep MiniCPM multimodal entries hidden until a real mtmd backend, complete checksums, supported ABI packaging, and end-to-end device tests exist.

**Gate:** Resume, failover, signature, checksum, corruption repair, multi-file cleanup, and ABI-matrix tests pass.

### Phase 8: Converge Architecture and Stabilize UI

- [ ] Break application-layer dependency cycles with explicit use cases and composition boundaries.
- [ ] Move save, delete, index refresh, model activation, and session orchestration out of presentation widgets.
- [ ] Remove duplicated providers, asynchronous `.value!` access, scattered route strings, dead repositories, and unused dependencies.
- [ ] Split production and test files over 500 lines by responsibility.
- [ ] Replace layout-sensitive widget tests with semantic actions and stable viewport-independent assertions.
- [ ] Update or remove stale plans, placeholder copy, and product claims that do not match implementation.

**Gate:** The feature dependency graph has no cycles, file-size rules pass, and existing user workflows have no behavioral regression.

### Phase 9: Release and Continuous Quality Gates

- [ ] Add integration coverage for authentication, migration, repositories, search, providers, clipboard clearing, and application lifecycle.
- [ ] Add Android instrumentation/device smoke tests for API 24 and the current target API.
- [ ] Require CI to run `flutter analyze`, all Dart tests, Android tests, migration fixtures, and debug/release builds.
- [ ] Run migration recovery drills, sensitive-log scans, dependency audits, and native-artifact provenance checks.
- [ ] Update README, version metadata, release notes, supported-device policy, threat model, and known limitations.

**Gate:** No open P0/P1 issue remains; clean install, upgrade, recovery, and release builds pass on real Android devices.

## Interface and Data Anchors

- Security data uses versioned key envelopes; `getDatabasePasswordMaterial()` must never return a fixed fallback.
- Database lifecycle exposes explicit `locked`, `opening`, `open`, `closing`, and `error` states; repositories may operate only while `open`.
- Encrypted fields use authenticated envelopes and are never represented as raw UTF-8 bytes with ciphertext naming.
- `EmbeddingChunk` carries field identity, configuration version, chunk version, and an irreversible keyed fingerprint.
- Legacy embedding indexes are disposable derived data and are rebuilt after the new schema is installed.
- Model registry entries use structured artifacts rather than concatenated paths or checksums.
- External-provider authorization is identified by a configuration fingerprint and is invalidated whenever endpoint, type, model, or credentials change.

## Planning and Test Rules

- Each phase gets an independent detailed plan; Phases 2, 4, 5, and 6 may be split into multiple child plans.
- Every behavior change begins with a failing test, followed by the minimal implementation, focused verification, full verification, and a scoped commit.
- Every migration tests clean install, each supported source version, interruption, repeat execution, rollback, and recovery.
- Every native change requires JVM coverage plus at least one instrumentation or real-device verification.
- Each phase commit contains only that phase's scope and must not bundle unrelated refactoring.
- A phase is complete only when its gate passes; documentation or UI copy cannot be used to claim unfinished functionality.

## Assumptions

- The target is a publishable security product rather than a demonstration that retains unsafe placeholders.
- Android is the release platform for this roadmap; equivalent iOS or desktop support is not promised.
- Existing passwords and notes must be preserved without loss.
- Embedding indexes, model caches, and download tasks may be rebuilt safely.
- External AI is explicitly optional and local unavailability never implies permission to send data externally.
- Before `v0.2.0`, the project must not claim completed field-level encryption, multimodal inference, or hardware-backed key protection.
