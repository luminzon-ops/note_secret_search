import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UnlockMethod {
  biometric,
  pin,
}

class LockSessionState {
  const LockSessionState({
    required this.isUnlocked,
    required this.pinEnabled,
    required this.lastUnlockMethod,
  });

  const LockSessionState.initial()
      : isUnlocked = false,
        pinEnabled = false,
        lastUnlockMethod = null;

  final bool isUnlocked;
  final bool pinEnabled;
  final UnlockMethod? lastUnlockMethod;

  LockSessionState copyWith({
    bool? isUnlocked,
    bool? pinEnabled,
    UnlockMethod? lastUnlockMethod,
    bool clearUnlockMethod = false,
  }) {
    return LockSessionState(
      isUnlocked: isUnlocked ?? this.isUnlocked,
      pinEnabled: pinEnabled ?? this.pinEnabled,
      lastUnlockMethod: clearUnlockMethod
          ? null
          : lastUnlockMethod ?? this.lastUnlockMethod,
    );
  }
}

class LockSessionController extends StateNotifier<LockSessionState> {
  LockSessionController() : super(const LockSessionState.initial());

  void markUnlocked(UnlockMethod method) {
    state = state.copyWith(isUnlocked: true, lastUnlockMethod: method);
  }

  void lock() {
    state = state.copyWith(isUnlocked: false, clearUnlockMethod: true);
  }

  void setPinEnabled(bool enabled) {
    state = state.copyWith(pinEnabled: enabled);
  }
}
