import 'dart:async';

abstract interface class SecureClipboardGateway {
  Future<void> setText(String value);

  Future<String?> getText();
}

abstract interface class SecureClipboardTimer {
  void cancel();
}

typedef ClipboardClearSecondsLoader = Future<int> Function();
typedef SecureClipboardTimerFactory =
    SecureClipboardTimer Function(Duration duration, void Function() callback);

class SecureClipboardController {
  SecureClipboardController({
    required SecureClipboardGateway gateway,
    required ClipboardClearSecondsLoader loadClearSeconds,
    SecureClipboardTimerFactory? createTimer,
  }) : _gateway = gateway,
       _loadClearSeconds = loadClearSeconds,
       _createTimer = createTimer ?? _createDartTimer;

  final SecureClipboardGateway _gateway;
  final ClipboardClearSecondsLoader _loadClearSeconds;
  final SecureClipboardTimerFactory _createTimer;
  SecureClipboardTimer? _clearTimer;
  var _generation = 0;
  var _disposed = false;

  Future<void> copySensitiveText(String value) async {
    final text = value;
    final generation = ++_generation;
    _cancelTimer();
    await _gateway.setText(text);
    if (_disposed || generation != _generation) {
      return;
    }

    final seconds = await _loadClearSeconds();
    if (_disposed || generation != _generation || seconds <= 0) {
      return;
    }
    _clearTimer = _createTimer(
      Duration(seconds: seconds),
      () => unawaited(_clearIfCurrent(generation, text)),
    );
  }

  Future<void> clearForLock() async {
    _generation += 1;
    _cancelTimer();
    try {
      await _gateway.setText('');
    } catch (_) {
      // Clipboard access is best-effort during lock and platform teardown.
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    _cancelTimer();
  }

  Future<void> _clearIfCurrent(int generation, String expectedText) async {
    if (_disposed || generation != _generation) {
      return;
    }
    final currentText = await _gateway.getText();
    if (_disposed || generation != _generation || currentText != expectedText) {
      return;
    }
    await _gateway.setText('');
  }

  void _cancelTimer() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}

SecureClipboardTimer _createDartTimer(
  Duration duration,
  void Function() callback,
) {
  return _DartSecureClipboardTimer(Timer(duration, callback));
}

class _DartSecureClipboardTimer implements SecureClipboardTimer {
  const _DartSecureClipboardTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}
