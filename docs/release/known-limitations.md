# Known Limitations

## v0.2.0

- MiniCPM / 多模态未实现；MiniCPM, mtmd, and mmproj assets must remain absent from packaged artifacts.
- Local llama.cpp runtime is arm64-only in the pinned AAR; non-arm64 devices may need external HTTPS providers for chat features.
- Release R8, resource shrink, and Flutter obfuscation are disabled until JNI, reflection, and native runtime characterization exists.
- External providers in Release must use HTTPS. Debug permits loopback HTTP for local development services such as Ollama.
- Clipboard cleanup is best-effort and avoids deleting content that another app or later copy replaced.
- The app does not claim protection against rooted devices, compromised OS services, hostile input methods, or out-of-process screen recording.
- Remote sync, remote catalog expansion, cloud backup, and account recovery are not part of v0.2.0.
