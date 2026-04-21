class PinState {
  const PinState({
    required this.enabled,
    required this.hasPinMaterial,
    required this.failedAttempts,
    required this.coolDownUntil,
    required this.lastFailureAt,
  });

  const PinState.initial()
      : enabled = false,
        hasPinMaterial = false,
        failedAttempts = 0,
        coolDownUntil = null,
        lastFailureAt = null;

  final bool enabled;
  final bool hasPinMaterial;
  final int failedAttempts;
  final DateTime? coolDownUntil;
  final DateTime? lastFailureAt;

  PinState copyWith({
    bool? enabled,
    bool? hasPinMaterial,
    int? failedAttempts,
    DateTime? coolDownUntil,
    DateTime? lastFailureAt,
    bool clearCoolDown = false,
  }) {
    return PinState(
      enabled: enabled ?? this.enabled,
      hasPinMaterial: hasPinMaterial ?? this.hasPinMaterial,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      coolDownUntil: clearCoolDown ? null : coolDownUntil ?? this.coolDownUntil,
      lastFailureAt: lastFailureAt ?? this.lastFailureAt,
    );
  }
}
