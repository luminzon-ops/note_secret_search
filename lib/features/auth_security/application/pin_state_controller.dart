import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_state.dart';

typedef PinCooldownScheduler =
    void Function(Duration delay, void Function() callback);

class PinStateController extends StateNotifier<PinState> {
  PinStateController({
    DateTime Function()? now,
    PinCooldownScheduler? scheduleCooldown,
  }) : _now = now ?? DateTime.now,
       _scheduleCooldown = scheduleCooldown ?? _scheduleWithTimer,
       super(const PinState.initial());

  final DateTime Function() _now;
  final PinCooldownScheduler _scheduleCooldown;
  int _coolDownGeneration = 0;
  bool _disposed = false;

  void configureEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
  }

  void markPinMaterialReady() {
    _invalidateCoolDown();
    state = state.copyWith(
      hasPinMaterial: true,
      failedAttempts: 0,
      clearCoolDown: true,
    );
  }

  void syncConfigured(bool configured) {
    _invalidateCoolDown();
    state = PinState(
      enabled: configured,
      hasPinMaterial: configured,
      failedAttempts: 0,
      coolDownUntil: null,
      lastFailureAt: null,
    );
  }

  bool get isInCoolDown {
    final coolDownUntil = state.coolDownUntil;
    return coolDownUntil != null && coolDownUntil.isAfter(_now());
  }

  void registerFailure({required int maxFailures, required Duration coolDown}) {
    final now = _now();
    final nextFailures = state.failedAttempts + 1;
    if (nextFailures >= maxFailures) {
      final coolDownUntil = now.add(coolDown);
      state = state.copyWith(
        failedAttempts: nextFailures,
        coolDownUntil: coolDownUntil,
        lastFailureAt: now,
      );
      _scheduleCoolDownExpiry(coolDownUntil);
      return;
    }

    state = state.copyWith(failedAttempts: nextFailures, lastFailureAt: now);
  }

  void resetFailures() {
    _invalidateCoolDown();
    state = state.copyWith(
      failedAttempts: 0,
      clearCoolDown: true,
      lastFailureAt: null,
    );
  }

  void _scheduleCoolDownExpiry(DateTime deadline) {
    final generation = ++_coolDownGeneration;

    void checkDeadline() {
      if (_disposed || generation != _coolDownGeneration) {
        return;
      }
      final currentDeadline = state.coolDownUntil;
      if (currentDeadline == null) {
        return;
      }
      final remaining = currentDeadline.difference(_now());
      if (remaining > Duration.zero) {
        _scheduleCooldown(remaining, checkDeadline);
        return;
      }
      state = state.copyWith(clearCoolDown: true);
    }

    final delay = deadline.difference(_now());
    _scheduleCooldown(delay.isNegative ? Duration.zero : delay, checkDeadline);
  }

  void _invalidateCoolDown() {
    _coolDownGeneration += 1;
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateCoolDown();
    super.dispose();
  }

  static void _scheduleWithTimer(Duration delay, void Function() callback) {
    Timer(delay, callback);
  }
}
