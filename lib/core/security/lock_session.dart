import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UnlockMethod { biometric, pin }

class LockSessionState {
  const LockSessionState({
    required this.isUnlocked,
    required this.pinEnabled,
    required this.lastUnlockMethod,
    required this.lockEpoch,
  });

  const LockSessionState.initial()
    : isUnlocked = false,
      pinEnabled = false,
      lastUnlockMethod = null,
      lockEpoch = 0;

  final bool isUnlocked;
  final bool pinEnabled;
  final UnlockMethod? lastUnlockMethod;
  final int lockEpoch;

  LockSessionState copyWith({
    bool? isUnlocked,
    bool? pinEnabled,
    UnlockMethod? lastUnlockMethod,
    int? lockEpoch,
    bool clearUnlockMethod = false,
  }) {
    return LockSessionState(
      isUnlocked: isUnlocked ?? this.isUnlocked,
      pinEnabled: pinEnabled ?? this.pinEnabled,
      lastUnlockMethod: clearUnlockMethod
          ? null
          : lastUnlockMethod ?? this.lastUnlockMethod,
      lockEpoch: lockEpoch ?? this.lockEpoch,
    );
  }
}

class LockSessionController extends StateNotifier<LockSessionState> {
  LockSessionController() : super(const LockSessionState.initial());

  bool get isUnlocked => state.isUnlocked;
  int get lockEpoch => state.lockEpoch;

  void markUnlocked(UnlockMethod method) {
    state = state.copyWith(isUnlocked: true, lastUnlockMethod: method);
  }

  void lock() {
    state = state.copyWith(
      isUnlocked: false,
      clearUnlockMethod: true,
      lockEpoch: state.lockEpoch + 1,
    );
  }

  void setPinEnabled(bool enabled) {
    state = state.copyWith(pinEnabled: enabled);
  }
}
