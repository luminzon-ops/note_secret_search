class SecuritySettings {
  const SecuritySettings({
    required this.pinEnabled,
    required this.biometricPreferred,
    required this.autoLockSeconds,
    required this.clipboardClearSeconds,
  });

  const SecuritySettings.defaults()
      : pinEnabled = false,
        biometricPreferred = true,
        autoLockSeconds = 30,
        clipboardClearSeconds = 60;

  final bool pinEnabled;
  final bool biometricPreferred;
  final int autoLockSeconds;
  final int clipboardClearSeconds;

  SecuritySettings copyWith({
    bool? pinEnabled,
    bool? biometricPreferred,
    int? autoLockSeconds,
    int? clipboardClearSeconds,
  }) {
    return SecuritySettings(
      pinEnabled: pinEnabled ?? this.pinEnabled,
      biometricPreferred: biometricPreferred ?? this.biometricPreferred,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
      clipboardClearSeconds: clipboardClearSeconds ?? this.clipboardClearSeconds,
    );
  }
}
