# Threat Model

## Protected Assets

- Vault contents, note bodies, secret usernames/passwords/websites/notes, tags, search index material, local model selections, external provider API keys, and consent state.
- Native runtime paths, tokenizer assets, and release APK/AAB provenance.

## In Scope

- Local-at-rest protection through SQLCipher, field encryption, native keyring, PIN/system authentication, lock invalidation, and screenshot/recent-task controls.
- Runtime privacy boundaries for external AI: explicit opt-in, per-send consent, provider fingerprinting, HTTPS-only Release endpoints, and gateway cancellation on config/privacy changes.
- Release-chain integrity: fixed AAR hash, artifact reuse, ABI/assets audit, signing environment isolation, and draft release attestation.

## Out of Scope

- Protection against a fully compromised OS, rooted device, hostile keyboard/IME, screen recording outside app control, or hardware memory extraction.
- Remote backup, remote sync, enterprise device management, or cloud-side account recovery.
- MiniCPM / multimodal inference and remote catalog expansion.

## Release Blocking Conditions

- Version/tag drift, non-clean release HEAD, signing certificate mismatch, AAR hash drift, release cleartext, unexpected ABI/native/assets, secret leakage, unresolved P0/P1, or release claims beyond implemented behavior.
