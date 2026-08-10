import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';

void main() {
  test('cooldown expiry publishes a state update without another failure', () {
    var now = DateTime(2026, 7, 16, 12);
    Duration? scheduledDelay;
    void Function()? scheduledCallback;
    final controller = PinStateController(
      now: () => now,
      scheduleCooldown: (delay, callback) {
        scheduledDelay = delay;
        scheduledCallback = callback;
      },
    )..markPinMaterialReady();
    addTearDown(controller.dispose);

    controller.registerFailure(
      maxFailures: 1,
      coolDown: const Duration(minutes: 1),
    );

    expect(scheduledDelay, const Duration(minutes: 1));
    expect(controller.state.coolDownUntil, now.add(scheduledDelay!));

    now = now.add(const Duration(minutes: 1));
    scheduledCallback!();

    expect(controller.state.coolDownUntil, isNull);
    expect(controller.isInCoolDown, isFalse);
  });
}
