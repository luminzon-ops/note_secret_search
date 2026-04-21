import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_state.dart';

class PinStateController extends StateNotifier<PinState> {
  PinStateController() : super(const PinState.initial());

  void configureEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
  }

  void markPinMaterialReady() {
    state = state.copyWith(hasPinMaterial: true, failedAttempts: 0, clearCoolDown: true);
  }

  bool get isInCoolDown {
    final coolDownUntil = state.coolDownUntil;
    return coolDownUntil != null && coolDownUntil.isAfter(DateTime.now());
  }

  void registerFailure({required int maxFailures, required Duration coolDown}) {
    final now = DateTime.now();
    final nextFailures = state.failedAttempts + 1;
    if (nextFailures >= maxFailures) {
      state = state.copyWith(
        failedAttempts: nextFailures,
        coolDownUntil: now.add(coolDown),
        lastFailureAt: now,
      );
      return;
    }

    state = state.copyWith(failedAttempts: nextFailures, lastFailureAt: now);
  }

  void resetFailures() {
    state = state.copyWith(failedAttempts: 0, clearCoolDown: true, lastFailureAt: null);
  }
}
