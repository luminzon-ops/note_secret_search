import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/secure_clipboard.dart';

void main() {
  test('clears copied text after configured delay', () async {
    final gateway = _MemoryClipboardGateway();
    final scheduler = _ManualTimerScheduler();
    final controller = SecureClipboardController(
      gateway: gateway,
      loadClearSeconds: () async => 60,
      createTimer: scheduler.create,
    );

    await controller.copySensitiveText('secret');
    expect(gateway.text, 'secret');
    expect(scheduler.lastDuration, const Duration(seconds: 60));

    await scheduler.fireLast();
    expect(gateway.text, '');
  });

  test('does not clear clipboard content replaced by another app', () async {
    final gateway = _MemoryClipboardGateway();
    final scheduler = _ManualTimerScheduler();
    final controller = SecureClipboardController(
      gateway: gateway,
      loadClearSeconds: () async => 60,
      createTimer: scheduler.create,
    );

    await controller.copySensitiveText('secret');
    gateway.text = 'replacement';

    await scheduler.fireLast();
    expect(gateway.text, 'replacement');
  });

  test('later copies supersede older clear timers', () async {
    final gateway = _MemoryClipboardGateway();
    final scheduler = _ManualTimerScheduler();
    final controller = SecureClipboardController(
      gateway: gateway,
      loadClearSeconds: () async => 60,
      createTimer: scheduler.create,
    );

    await controller.copySensitiveText('first');
    final firstTimer = scheduler.lastTimer;
    await controller.copySensitiveText('second');

    await firstTimer.fire();
    expect(gateway.text, 'second');
  });

  test('lock clears immediately and cancels pending timeout', () async {
    final gateway = _MemoryClipboardGateway();
    final scheduler = _ManualTimerScheduler();
    final controller = SecureClipboardController(
      gateway: gateway,
      loadClearSeconds: () async => 60,
      createTimer: scheduler.create,
    );

    await controller.copySensitiveText('secret');
    final timer = scheduler.lastTimer;
    await controller.clearForLock();

    expect(gateway.text, '');
    expect(timer.cancelled, isTrue);
  });

  test('dispose cancels pending clear timer', () async {
    final gateway = _MemoryClipboardGateway();
    final scheduler = _ManualTimerScheduler();
    final controller = SecureClipboardController(
      gateway: gateway,
      loadClearSeconds: () async => 60,
      createTimer: scheduler.create,
    );

    await controller.copySensitiveText('secret');
    final timer = scheduler.lastTimer;
    controller.dispose();

    expect(timer.cancelled, isTrue);
    await timer.fire();
    expect(gateway.text, 'secret');
  });
}

class _MemoryClipboardGateway implements SecureClipboardGateway {
  String? text;

  @override
  Future<String?> getText() async => text;

  @override
  Future<void> setText(String value) async {
    text = value;
  }
}

class _ManualTimerScheduler {
  final List<_ManualTimer> timers = <_ManualTimer>[];
  Duration? lastDuration;

  _ManualTimer get lastTimer => timers.last;

  SecureClipboardTimer create(Duration duration, void Function() callback) {
    lastDuration = duration;
    final timer = _ManualTimer(callback);
    timers.add(timer);
    return timer;
  }

  Future<void> fireLast() => lastTimer.fire();
}

class _ManualTimer implements SecureClipboardTimer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }

  Future<void> fire() async {
    if (!cancelled) {
      _callback();
      await Future<void>.delayed(Duration.zero);
    }
  }
}
