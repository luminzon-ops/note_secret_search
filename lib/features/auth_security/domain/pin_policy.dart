abstract final class AppPinPolicy {
  static const int minimumLength = 4;
  static const int maximumLength = 8;
  static const int maxFailures = 5;
  static const Duration coolDown = Duration(minutes: 1);
}
