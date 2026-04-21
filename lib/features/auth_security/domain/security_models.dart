enum PrivacyMode {
  strict,
  balanced,
  custom,
}

enum AutoLockDuration {
  immediate,
  seconds30,
  minute1,
  minutes5,
}

enum BiometricAvailability {
  available,
  unavailable,
  notEnrolled,
}

class PinPolicy {
  const PinPolicy({
    required this.enabled,
    required this.maxFailures,
    required this.coolDownSeconds,
  });

  final bool enabled;
  final int maxFailures;
  final int coolDownSeconds;
}
