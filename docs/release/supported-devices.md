# Supported Devices

## v0.2.1 Policy

- Android SDK and ABI policy remains unchanged from v0.2.0.
- Physical hotfix evidence is restricted to Huawei SPN-AL00 / API 29 / arm64-v8a with serial `H8B4C19731000256`.
- Device acceptance requires one cancelled biometric attempt with lock-screen recovery, two successful fingerprint unlocks including a cold start, clean Logcat, and unchanged GGUF inventories.
- The v0.2.1 debug APK installed on the Huawei device is a local validation artifact only; it is not a public distribution binary.

## v0.2.0 Policy

- Minimum Android API: 24.
- Target Android API: 34.
- Compile SDK: 36.
- Release smoke coverage: API 24 and API 34 emulator jobs consume the package-once artifacts.
- Physical closeout evidence: Huawei SPN-AL00 / API 29, serial-gated on August 10, 2026.

## Runtime Notes

- ONNX Runtime Mobile embedding libraries are packaged for the Android ABI set tracked by `config/release/release_artifact_policy.json`.
- The llama.cpp local LLM AAR contains only the arm64 runtime library and keeps SHA-256 `9583871b4179ae48ce3c57796fad21580167de4183ca6c28efdc2ed4724f9b41`.
- Devices without compatible local LLM runtime support can still use password, note, encrypted storage, keyword search, and external HTTPS provider features.

## Release Blocking Device Evidence

- A new signed release candidate must pass clean install, cold start, force-stop, relaunch, and v0.1.0 upgrade/data-preservation smoke before publishing.
- Phase 8 Huawei BGE and sensitive-log suites are reused unless runtime source, AAR, native packaging, tokenizer/assets, relevant instrumentation, ABI, or dependency inputs materially change.
- The v0.2.0 debug APK installed on the Huawei device is a local validation artifact only; it is not a public distribution binary.
