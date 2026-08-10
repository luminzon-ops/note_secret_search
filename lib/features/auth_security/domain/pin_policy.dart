abstract final class AppPinPolicy {
  static const int minimumLength = 4;
  static const int maximumLength = 8;
  static const int maxFailures = 5;
  static const Duration coolDown = Duration(minutes: 1);

  static PinValidationFailure? validate(String raw) {
    if (raw.length < minimumLength || raw.length > maximumLength) {
      return PinValidationFailure.invalidLength;
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(raw)) {
      return PinValidationFailure.nonNumeric;
    }
    return null;
  }
}

enum PinValidationFailure { invalidLength, nonNumeric }
