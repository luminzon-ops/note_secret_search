# Changelog

## 0.2.1+3 - 2026-08-13

- Fixes Huawei biometric unlock crashes caused by clearing read-only `StandardMessageCodec` byte views.
- Allows authenticated results to complete during the temporary inactive state while keeping sensitive content shielded until resume.
- Restores the secure lock screen after system authentication is cancelled or fails, and adds sanitized fallback handling for unexpected bridge errors.
- Makes release notes tag-driven and generalizes the Huawei closeout gate for versioned hotfix validation.

## 0.2.0+2 - 2026-08-05

- Adds Phase 9 release readiness contracts for CI, artifact provenance, version ownership, signing boundaries, and release documentation.
- Routes sensitive copy actions through a secure clipboard controller that honors the persisted 60 second cleanup setting and clears best-effort on lock.
- Enforces external provider endpoint policy: Release accepts HTTPS only; Debug accepts HTTPS or loopback HTTP.
- Centralizes Android release metadata around `pubspec.yaml` version `0.2.0+2`, Flutter `3.41.5`, Dart `3.11.3`, Java 17, Gradle `8.11.1`, AGP `8.9.1`, Kotlin `2.2.20`, SDK 36/34/24, and NDK `28.2.13676358`.
- Adds package-once CI artifact flow for debug APK, androidTest APK, unsigned release APK, and release AAB, followed by audit, API smoke, protected signing, attestation, and draft release jobs.

## 0.1.0+1

- Baseline private notes, password entries, encrypted storage, search, and local AI runtime work completed across earlier repair phases.
