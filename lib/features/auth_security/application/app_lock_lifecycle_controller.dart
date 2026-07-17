import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';

class AppLockLifecycleController with WidgetsBindingObserver {
  AppLockLifecycleController({
    required LockSessionController sessionController,
    required Future<int> Function() autoLockSecondsLoader,
    required ScreenshotProtectionGateway screenshotProtectionGateway,
    required Future<void> Function() lockApplication,
  }) : _sessionController = sessionController,
       _autoLockSecondsLoader = autoLockSecondsLoader,
       _screenshotProtectionGateway = screenshotProtectionGateway,
       _lockApplication = lockApplication;

  final LockSessionController _sessionController;
  final Future<int> Function() _autoLockSecondsLoader;
  final ScreenshotProtectionGateway _screenshotProtectionGateway;
  final Future<void> Function() _lockApplication;
  DateTime? _pausedAt;
  Future<void> _lifecycleQueue = Future<void>.value();
  AppLifecycleState? _latestLifecycleState;
  Timer? _autoLockTimer;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _started = true;
  }

  void dispose() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    if (!_started) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previousState = _latestLifecycleState;
    _latestLifecycleState = state;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        if (previousState == null ||
            previousState == AppLifecycleState.resumed) {
          _pausedAt = DateTime.now();
        } else {
          _pausedAt ??= DateTime.now();
        }
        _enqueue(_handleBackgroundTransition);
      case AppLifecycleState.resumed:
        _enqueue(_handleResume);
      case AppLifecycleState.detached:
        if (previousState == null ||
            previousState == AppLifecycleState.resumed) {
          _pausedAt = DateTime.now();
        } else {
          _pausedAt ??= DateTime.now();
        }
        _enqueue(_lockApplication);
    }
  }

  void _enqueue(Future<void> Function() operation) {
    _lifecycleQueue = _lifecycleQueue
        .then((_) => operation())
        .catchError((Object _, StackTrace __) => _lockApplication());
  }

  Future<void> _handleBackgroundTransition() async {
    await _screenshotProtectionGateway.updateRecentTaskProtection(
      obscured: true,
    );

    final autoLockSeconds = await _autoLockSecondsLoader();
    if (autoLockSeconds <= 0) {
      await _lockApplication();
      return;
    }
    if (_latestLifecycleState != AppLifecycleState.resumed) {
      _scheduleAutoLock(autoLockSeconds);
    }
  }

  Future<void> _handleResume() async {
    if (_latestLifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final pausedAt = _pausedAt;
    _pausedAt = null;
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    if (pausedAt != null) {
      final autoLockSeconds = await _autoLockSecondsLoader();
      final elapsed = DateTime.now().difference(pausedAt).inSeconds;
      if (autoLockSeconds <= 0 || elapsed >= autoLockSeconds) {
        await _lockApplication();
      }
    }

    if (_latestLifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (!_sessionController.isUnlocked) {
      return;
    }
    await _screenshotProtectionGateway.updateRecentTaskProtection(
      obscured: false,
    );
  }

  void _scheduleAutoLock(int autoLockSeconds) {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(Duration(seconds: autoLockSeconds), () {
      _autoLockTimer = null;
      _enqueue(_lockApplication);
    });
  }
}
