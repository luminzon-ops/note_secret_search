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
  })  : _biometricGateway = biometricGateway,
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
    final passwordMaterial = await _secureKeyGateway.getDatabasePasswordMaterial();
    final availability = await _biometricGateway.getAvailability();
    _logger.info('Biometric availability: ${availability.name}');
    _logger.info('Database password material ready: ${passwordMaterial.isNotEmpty}');
    _sessionController.lock();
  }

  Future<bool> unlockWithBiometrics() async {
    final granted = await _biometricGateway.authenticate();
    if (granted) {
      _sessionController.markUnlocked(UnlockMethod.biometric);
      _pinStateController.resetFailures();
    }
    return granted;
  }

  void unlockWithPin() {
    _sessionController.markUnlocked(UnlockMethod.pin);
    _pinStateController.resetFailures();
  }

  void registerPinFailure({required int maxFailures, required Duration coolDown}) {
    _pinStateController.registerFailure(maxFailures: maxFailures, coolDown: coolDown);
  }

  void enablePinFallback(bool enabled) {
    _sessionController.setPinEnabled(enabled);
    _pinStateController.configureEnabled(enabled);
    if (enabled) {
      _pinStateController.markPinMaterialReady();
    }
  }
}
