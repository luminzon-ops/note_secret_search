import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/app_lock_lifecycle_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/presentation/app_lifecycle_guard.dart';

void main() {
  test(
    'inactive only shields and does not trigger immediate auto-lock',
    () async {
      final sessionController = LockSessionController()
        ..markUnlocked(UnlockMethod.biometric);
      final initialLockEpoch = sessionController.lockEpoch;
      var lockCalls = 0;
      final obscureBlocker = Completer<void>();
      final gateway = _RecordingScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          if (obscured && !obscureBlocker.isCompleted) {
            await obscureBlocker.future;
          }
        },
      );
      final controller = AppLockLifecycleController(
        sessionController: sessionController,
        autoLockSecondsLoader: () async => 0,
        screenshotProtectionGateway: gateway,
        lockApplication: () async {
          lockCalls += 1;
          sessionController.lock();
        },
      );

      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await _waitUntil(() => gateway.obscuredUpdates.isNotEmpty);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _drainEventQueue();

      expect(gateway.obscuredUpdates, [true]);

      obscureBlocker.complete();
      await _waitUntil(() => gateway.obscuredUpdates.length == 2);

      expect(gateway.obscuredUpdates, [true, false]);
      expect(sessionController.state.isUnlocked, isTrue);
      expect(sessionController.lockEpoch, initialLockEpoch);
      expect(lockCalls, 0);
    },
  );

  test('inactive shield failure does not lock or increment epoch', () async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final initialLockEpoch = sessionController.lockEpoch;
    var lockCalls = 0;
    final gateway = _RecordingScreenshotProtectionGateway(
      onUpdate: (obscured) async {
        if (obscured) {
          throw StateError('shield unavailable');
        }
      },
    );
    final controller = AppLockLifecycleController(
      sessionController: sessionController,
      autoLockSecondsLoader: () async => 0,
      screenshotProtectionGateway: gateway,
      lockApplication: () async {
        lockCalls += 1;
        sessionController.lock();
      },
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await _drainEventQueue();

    expect(gateway.obscuredUpdates, [true]);
    expect(sessionController.isUnlocked, isTrue);
    expect(sessionController.lockEpoch, initialLockEpoch);
    expect(lockCalls, 0);
  });

  test(
    'stale resumed work does not unshield after a newer inactive transition',
    () async {
      final sessionController = LockSessionController()
        ..markUnlocked(UnlockMethod.biometric);
      final firstObscureBlocker = Completer<void>();
      var obscuredCallCount = 0;
      final gateway = _RecordingScreenshotProtectionGateway(
        onUpdate: (obscured) async {
          if (obscured) {
            obscuredCallCount += 1;
            if (obscuredCallCount == 1) {
              await firstObscureBlocker.future;
            }
          }
        },
      );
      final controller = AppLockLifecycleController(
        sessionController: sessionController,
        autoLockSecondsLoader: () async => 1,
        screenshotProtectionGateway: gateway,
        lockApplication: () async => sessionController.lock(),
      );

      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await _waitUntil(() => gateway.obscuredUpdates.isNotEmpty);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      firstObscureBlocker.complete();

      await _waitUntil(() => gateway.obscuredUpdates.length >= 2);
      expect(gateway.obscuredUpdates, [true, true]);

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _drainEventQueue();

      expect(gateway.obscuredUpdates, [true, true, false]);
      expect(sessionController.state.isUnlocked, isTrue);
    },
  );

  test(
    'resumed lifecycle keeps shield when background transition locked',
    () async {
      final sessionController = LockSessionController()
        ..markUnlocked(UnlockMethod.biometric);
      final gateway = _RecordingScreenshotProtectionGateway();
      final controller = AppLockLifecycleController(
        sessionController: sessionController,
        autoLockSecondsLoader: () async => 0,
        screenshotProtectionGateway: gateway,
        lockApplication: () async => sessionController.lock(),
      );

      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await _waitUntil(() => !sessionController.state.isUnlocked);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _drainEventQueue();

      expect(gateway.obscuredUpdates, [true]);
      expect(sessionController.state.isUnlocked, isFalse);
    },
  );

  test('background settings failure locks and leaves shield enabled', () async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final gateway = _RecordingScreenshotProtectionGateway();
    final controller = AppLockLifecycleController(
      sessionController: sessionController,
      autoLockSecondsLoader: () =>
          Future<int>.error(StateError('settings unavailable')),
      screenshotProtectionGateway: gateway,
      lockApplication: () async => sessionController.lock(),
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await _drainEventQueue();

    expect(gateway.obscuredUpdates, [true]);
    expect(sessionController.state.isUnlocked, isFalse);
  });

  test('resume settings failure locks before shield removal', () async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final gateway = _RecordingScreenshotProtectionGateway();
    var loadCount = 0;
    final controller = AppLockLifecycleController(
      sessionController: sessionController,
      autoLockSecondsLoader: () async {
        loadCount += 1;
        if (loadCount == 1) {
          return 60;
        }
        throw StateError('settings unavailable');
      },
      screenshotProtectionGateway: gateway,
      lockApplication: () async => sessionController.lock(),
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await _waitUntil(() => loadCount == 1);

    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drainEventQueue();

    expect(gateway.obscuredUpdates, [true]);
    expect(sessionController.state.isUnlocked, isFalse);
  });

  test('resume shield failure keeps the session locked', () async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final gateway = _RecordingScreenshotProtectionGateway(
      onUpdate: (obscured) {
        if (!obscured) {
          return Future<void>.error(StateError('shield unavailable'));
        }
        return Future<void>.value();
      },
    );
    final controller = AppLockLifecycleController(
      sessionController: sessionController,
      autoLockSecondsLoader: () async => 60,
      screenshotProtectionGateway: gateway,
      lockApplication: () async => sessionController.lock(),
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await _waitUntil(
      () =>
          gateway.obscuredUpdates.length == 1 && gateway.obscuredUpdates.single,
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drainEventQueue();

    expect(gateway.obscuredUpdates, [true, false]);
    expect(sessionController.state.isUnlocked, isFalse);
  });

  test('elapsed auto-lock timeout is checked before shield removal', () async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final gateway = _RecordingScreenshotProtectionGateway();
    final controller = AppLockLifecycleController(
      sessionController: sessionController,
      autoLockSecondsLoader: () async => 1,
      screenshotProtectionGateway: gateway,
      lockApplication: () async => sessionController.lock(),
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await _waitUntil(
      () =>
          gateway.obscuredUpdates.length == 1 && gateway.obscuredUpdates.single,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _drainEventQueue();

    expect(gateway.obscuredUpdates, [true]);
    expect(sessionController.state.isUnlocked, isFalse);
  });

  test('background timer locks before the app resumes', () async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final gateway = _RecordingScreenshotProtectionGateway();
    var lockCalls = 0;
    final controller = AppLockLifecycleController(
      sessionController: sessionController,
      autoLockSecondsLoader: () async => 1,
      screenshotProtectionGateway: gateway,
      lockApplication: () async {
        lockCalls += 1;
        sessionController.lock();
      },
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await _drainEventQueue();

    expect(lockCalls, 1);
    expect(sessionController.isUnlocked, isFalse);
  });

  testWidgets('AppLifecycleGuard forwards inactive and hidden transitions', (
    tester,
  ) async {
    final sessionController = LockSessionController()
      ..markUnlocked(UnlockMethod.biometric);
    final initialLockEpoch = sessionController.lockEpoch;
    final gateway = _RecordingScreenshotProtectionGateway();
    final controller = AppLockLifecycleController(
      sessionController: sessionController,
      autoLockSecondsLoader: () async => 0,
      screenshotProtectionGateway: gateway,
      lockApplication: () async => sessionController.lock(),
    );
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockLifecycleControllerProvider.overrideWithValue(controller),
        ],
        child: const AppLifecycleGuard(child: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await _waitUntil(() => gateway.obscuredUpdates.isNotEmpty);

    expect(gateway.obscuredUpdates, [true]);
    expect(sessionController.isUnlocked, isTrue);
    expect(sessionController.lockEpoch, initialLockEpoch);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    await _waitUntil(() => !sessionController.isUnlocked);

    expect(gateway.obscuredUpdates, [true, true]);
    expect(sessionController.lockEpoch, initialLockEpoch + 1);
  });
}

class _RecordingScreenshotProtectionGateway
    implements ScreenshotProtectionGateway {
  _RecordingScreenshotProtectionGateway({this.onUpdate});

  final Future<void> Function(bool obscured)? onUpdate;
  final List<bool> obscuredUpdates = [];

  @override
  Future<void> enableSensitiveWindowProtection() async {}

  @override
  Future<void> updateRecentTaskProtection({required bool obscured}) async {
    obscuredUpdates.add(obscured);
    await onUpdate?.call(obscured);
  }
}

Future<void> _drainEventQueue() async {
  for (var index = 0; index < 10; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100; index += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached before the test timeout.');
}
