import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';

void main() {
  test('error logs only the fixed event name and exception type', () {
    final sink = _RecordingAppLogSink();
    final logger = AppLogger(sink: sink);

    logger.error(
      'local_llm_generation_failed',
      StateError('PROMPT_SENTINEL'),
      StackTrace.fromString('STACK_SENTINEL'),
    );

    expect(sink.records, hasLength(1));
    expect(
      sink.records.single,
      const _LogRecord(
        message: 'local_llm_generation_failed error_type=StateError',
        name: 'note_secret_search.error',
        level: 1000,
      ),
    );
    expect(sink.records.single.message, isNot(contains('PROMPT_SENTINEL')));
    expect(sink.records.single.message, isNot(contains('STACK_SENTINEL')));
  });

  test('invalid event names fail closed for every log level', () {
    final sink = _RecordingAppLogSink();
    final logger = AppLogger(sink: sink);

    logger.info('MODEL_PATH_SENTINEL=/private/model.gguf');
    logger.warning('PROMPT_SENTINEL user content');
    logger.error(
      'DATABASE_KEY_SENTINEL',
      StateError('raw error'),
      StackTrace.current,
    );

    expect(sink.records.map((record) => record.message), [
      'invalid_log_event',
      'invalid_log_event',
      'invalid_log_event error_type=StateError',
    ]);
  });

  test('event names are limited to 64 characters', () {
    final sink = _RecordingAppLogSink();
    final logger = AppLogger(sink: sink);
    final maximumLengthEvent = List.filled(64, 'a').join();

    logger.info(maximumLengthEvent);
    logger.warning('${maximumLengthEvent}a');

    expect(sink.records.map((record) => record.message), [
      maximumLengthEvent,
      'invalid_log_event',
    ]);
  });
}

class _RecordingAppLogSink implements AppLogSink {
  final records = <_LogRecord>[];

  @override
  void write({
    required String message,
    required String name,
    required int level,
  }) {
    records.add(_LogRecord(message: message, name: name, level: level));
  }
}

class _LogRecord {
  const _LogRecord({
    required this.message,
    required this.name,
    required this.level,
  });

  final String message;
  final String name;
  final int level;

  @override
  bool operator ==(Object other) {
    return other is _LogRecord &&
        other.message == message &&
        other.name == name &&
        other.level == level;
  }

  @override
  int get hashCode => Object.hash(message, name, level);
}
