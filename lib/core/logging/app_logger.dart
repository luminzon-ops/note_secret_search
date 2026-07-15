import 'dart:developer' as developer;

abstract interface class AppLogSink {
  void write({
    required String message,
    required String name,
    required int level,
  });
}

class AppLogger {
  const AppLogger({AppLogSink? sink}) : _sink = sink;

  static const _invalidEvent = 'invalid_log_event';
  static const _maximumEventLength = 64;
  static final _eventPattern = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');

  final AppLogSink? _sink;

  void info(String event) {
    _write(
      message: _sanitizeEvent(event),
      name: 'note_secret_search.info',
      level: 0,
    );
  }

  void warning(String event) {
    _write(
      message: _sanitizeEvent(event),
      name: 'note_secret_search.warning',
      level: 900,
    );
  }

  void error(String event, Object error, StackTrace stackTrace) {
    final sanitizedEvent = _sanitizeEvent(event);
    _write(
      message: '$sanitizedEvent error_type=${error.runtimeType}',
      name: 'note_secret_search.error',
      level: 1000,
    );
  }

  String _sanitizeEvent(String event) {
    if (event.length > _maximumEventLength || !_eventPattern.hasMatch(event)) {
      return _invalidEvent;
    }
    return event;
  }

  void _write({
    required String message,
    required String name,
    required int level,
  }) {
    final sink = _sink;
    if (sink != null) {
      sink.write(message: message, name: name, level: level);
      return;
    }
    developer.log(message, name: name, level: level);
  }
}
