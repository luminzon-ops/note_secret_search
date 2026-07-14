import 'package:flutter/widgets.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';

class AppLockLifecycleController with WidgetsBindingObserver {
  AppLockLifecycleController({
    required LockSessionController sessionController,
    required Future<int> Function() autoLockSecondsLoader,
    required ScreenshotProtectionGateway screenshotProtectionGateway,
  }) : _sessionController = sessionController,
       _autoLockSecondsLoader = autoLockSecondsLoader,
       _screenshotProtectionGateway = screenshotProtectionGateway;

  final LockSessionController _sessionController;
  final Future<int> Function() _autoLockSecondsLoader;
  final ScreenshotProtectionGateway _screenshotProtectionGateway;
  DateTime? _pausedAt;
  Future<void> _lifecycleQueue = Future<void>.value();
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _started = true;
  }

  void dispose() {
    if (!_started) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        _pausedAt ??= DateTime.now();
        _enqueue(_handleBackgroundTransition);
      case AppLifecycleState.resumed:
        _enqueue(_handleResume);
      case AppLifecycleState.detached:
        _pausedAt ??= DateTime.now();
        _enqueue(
          () => _screenshotProtectionGateway.updateRecentTaskProtection(
            obscured: true,
          ),
        );
    }
  }

  void _enqueue(Future<void> Function() operation) {
    _lifecycleQueue = _lifecycleQueue.then((_) => operation()).catchError((
      Object _,
      StackTrace __,
    ) {
      _sessionController.lock();
    });
  }

  Future<void> _handleBackgroundTransition() async {
    await _screenshotProtectionGateway.updateRecentTaskProtection(
      obscured: true,
    );

    final autoLockSeconds = await _autoLockSecondsLoader();
    if (autoLockSeconds == 0) {
      _sessionController.lock();
    }
  }

  Future<void> _handleResume() async {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt != null) {
      final autoLockSeconds = await _autoLockSecondsLoader();
      final elapsed = DateTime.now().difference(pausedAt).inSeconds;
      if (autoLockSeconds == 0 || elapsed >= autoLockSeconds) {
        _sessionController.lock();
      }
    }

    if (!_sessionController.isUnlocked) {
      _sessionController.lock();
      return;
    }
    await _screenshotProtectionGateway.updateRecentTaskProtection(
      obscured: false,
    );
  }
}
