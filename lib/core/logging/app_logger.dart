import 'dart:developer' as developer;

class AppLogger {
  const AppLogger();

  void info(String message) {
    developer.log(message, name: 'note_secret_search.info');
  }

  void warning(String message) {
    developer.log(message, name: 'note_secret_search.warning', level: 900);
  }

  void error(String message, Object error, StackTrace stackTrace) {
    developer.log(
      message,
      name: 'note_secret_search.error',
      error: error,
      stackTrace: stackTrace,
      level: 1000,
    );
  }
}
