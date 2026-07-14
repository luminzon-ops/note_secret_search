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
  }) : _biometricGateway = biometricGateway,
       _screenshotProtectionGateway = screenshotProtectionGateway,
       _secureKeyGateway = secureKeyGateway,
       _sessionController = sessionController,
       _pinStateController = pinStateController,
       _logger = logger;

  final BiometricGateway _biometricGateway;
  final ScreenshotProtectionGateway _screenshotProtectionGateway;
  final SecureKeyGateway _secureKeyGateway;
  final LockSessionController _sessionController;
  final PinStateController _pinStateController;
  final AppLogger _logger;

  Future<void> initialize() async {
    await _screenshotProtectionGateway.enableSensitiveWindowProtection();
    await _secureKeyGateway.ensureRootKey();
    final availability = await _biometricGateway.getAvailability();
    _logger.info('Biometric availability: ${availability.name}');
    _sessionController.lock();
  }

  Future<bool> unlockWithBiometrics() async {
    final granted = await _biometricGateway.authenticate();
    if (!granted) {
      return false;
    }
    return _completeUnlock(UnlockMethod.biometric);
  }

  Future<bool> unlockWithPin() {
    return _completeUnlock(UnlockMethod.pin);
  }

  Future<bool> _completeUnlock(UnlockMethod method) async {
    try {
      await _screenshotProtectionGateway.updateRecentTaskProtection(
        obscured: false,
      );
    } catch (_) {
      _sessionController.lock();
      return false;
    }

    _sessionController.markUnlocked(method);
    _pinStateController.resetFailures();
    return true;
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
