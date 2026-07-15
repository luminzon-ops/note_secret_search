import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';

class SecurityOrchestrator {
  SecurityOrchestrator({
    required BiometricGateway biometricGateway,
    required ScreenshotProtectionGateway screenshotProtectionGateway,
    required SecureKeyGateway secureKeyGateway,
    required LockSessionController sessionController,
    required PinStateController pinStateController,
    required AppLogger logger,
    required bool Function() appIsForeground,
  }) : _biometricGateway = biometricGateway,
       _screenshotProtectionGateway = screenshotProtectionGateway,
       _secureKeyGateway = secureKeyGateway,
       _sessionController = sessionController,
       _pinStateController = pinStateController,
       _logger = logger,
       _appIsForeground = appIsForeground;

  final BiometricGateway _biometricGateway;
  final ScreenshotProtectionGateway _screenshotProtectionGateway;
  final SecureKeyGateway _secureKeyGateway;
  final LockSessionController _sessionController;
  final PinStateController _pinStateController;
  final AppLogger _logger;
  final bool Function() _appIsForeground;

  Future<void> initialize() async {
    await _screenshotProtectionGateway.enableSensitiveWindowProtection();
    await _secureKeyGateway.ensureRootKey();
    await _biometricGateway.getAvailability();
    _logger.info('security_initialized');
    _sessionController.lock();
  }

  Future<bool> unlockWithBiometrics() async {
    final expectedLockEpoch = _sessionController.lockEpoch;
    final granted = await _biometricGateway.authenticate();
    if (!granted) {
      return false;
    }
    return _completeUnlock(
      UnlockMethod.biometric,
      expectedLockEpoch: expectedLockEpoch,
    );
  }

  Future<bool> unlockWithPin({required int expectedLockEpoch}) {
    return _completeUnlock(
      UnlockMethod.pin,
      expectedLockEpoch: expectedLockEpoch,
    );
  }

  Future<bool> _completeUnlock(
    UnlockMethod method, {
    required int expectedLockEpoch,
  }) async {
    if (!_canCompleteUnlock(expectedLockEpoch)) {
      return false;
    }

    try {
      await _screenshotProtectionGateway.updateRecentTaskProtection(
        obscured: false,
      );
    } catch (_) {
      _sessionController.lock();
      return false;
    }

    if (!_canCompleteUnlock(expectedLockEpoch)) {
      await _restoreShieldAfterStaleUnlock();
      return false;
    }

    _sessionController.markUnlocked(method);
    _pinStateController.resetFailures();
    return true;
  }

  bool _canCompleteUnlock(int expectedLockEpoch) {
    return !_sessionController.isUnlocked &&
        _sessionController.lockEpoch == expectedLockEpoch &&
        _appIsForeground();
  }

  Future<void> _restoreShieldAfterStaleUnlock() async {
    if (_sessionController.isUnlocked && _appIsForeground()) {
      return;
    }
    try {
      await _screenshotProtectionGateway.updateRecentTaskProtection(
        obscured: true,
      );
    } catch (_) {
      _sessionController.lock();
    }
  }

  void registerPinFailure({
    required int maxFailures,
    required Duration coolDown,
  }) {
    _pinStateController.registerFailure(
      maxFailures: maxFailures,
      coolDown: coolDown,
    );
  }

  void enablePinFallback(bool enabled) {
    _sessionController.setPinEnabled(enabled);
    _pinStateController.configureEnabled(enabled);
    if (enabled) {
      _pinStateController.markPinMaterialReady();
    }
  }
}
