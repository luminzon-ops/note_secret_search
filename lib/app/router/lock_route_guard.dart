import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_state.dart';
import 'package:note_secret_search/shared/navigation/app_destination.dart';

final postUnlockNavigationProvider = Provider<PostUnlockNavigation>((ref) {
  final navigation = PostUnlockNavigation();
  ref.onDispose(navigation.dispose);
  return navigation;
});

class LockRouteGuard {
  LockRouteGuard({required PostUnlockNavigation navigation})
    : _navigation = navigation;

  final PostUnlockNavigation _navigation;

  String? redirect({
    required LockSessionState session,
    required PinState pinState,
    required Uri uri,
  }) {
    if (!session.isUnlocked) {
      final pinUnlockAllowed =
          uri.path == AppDestination.pinUnlock &&
          session.pinEnabled &&
          pinState.enabled &&
          pinState.hasPinMaterial;
      if (pinUnlockAllowed || uri.path == AppDestination.vault) {
        return null;
      }
      if (AppDestination.isProtected(uri)) {
        _navigation.capture(uri);
      }
      return AppDestination.vault;
    }

    if (_navigation.pinResetRequired) {
      if (uri.path == AppDestination.pinSetup) {
        return null;
      }
      if (AppDestination.isProtected(uri) &&
          uri.path != AppDestination.vault) {
        _navigation.capture(uri);
      }
      return AppDestination.pinSetup;
    }

    if (_navigation.consumePinResetResume()) {
      return _navigation.takePending()?.toString() ?? AppDestination.vault;
    }

    final pending = _navigation.pendingDestination;
    if (pending != null && pending == uri) {
      _navigation.discardPending();
      return null;
    }

    if (uri.path == AppDestination.pinUnlock ||
        uri.path == AppDestination.vault) {
      final destination = _navigation.takePending();
      if (destination != null && destination.path != uri.path) {
        return destination.toString();
      }
      if (uri.path == AppDestination.pinUnlock) {
        return AppDestination.vault;
      }
    }
    return null;
  }
}

class PostUnlockNavigation extends ChangeNotifier {
  Uri? _pendingDestination;
  bool _pinResetRequired = false;
  bool _resumeAfterPinReset = false;

  Uri? get pendingDestination => _pendingDestination;
  bool get pinResetRequired => _pinResetRequired;

  void capture(Uri destination) {
    if (!AppDestination.isProtected(destination) ||
        destination.path == AppDestination.vault) {
      return;
    }
    _pendingDestination = destination;
  }

  void requirePinReset() {
    if (_pinResetRequired) {
      return;
    }
    _pinResetRequired = true;
    notifyListeners();
  }

  bool completePinReset() {
    if (!_pinResetRequired) {
      return false;
    }
    _pinResetRequired = false;
    _resumeAfterPinReset = true;
    notifyListeners();
    return true;
  }

  bool consumePinResetResume() {
    if (!_resumeAfterPinReset) {
      return false;
    }
    _resumeAfterPinReset = false;
    return true;
  }

  Uri? takePending() {
    final destination = _pendingDestination;
    _pendingDestination = null;
    return destination;
  }

  void discardPending() {
    _pendingDestination = null;
  }
}
