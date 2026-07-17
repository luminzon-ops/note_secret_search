import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';

class SecurityOrchestrator {
  SecurityOrchestrator({
    required BiometricGateway biometricGateway,
    required ScreenshotProtectionGateway screenshotProtectionGateway,
    required SecureKeyGateway secureKeyGateway,
    required LockSessionController sessionController,
    required PinStateController pinStateController,
    required DatabaseSessionKeyStore sessionKeyStore,
    required AppLogger logger,
    required bool Function() appIsForeground,
  }) : _biometricGateway = biometricGateway,
       _screenshotProtectionGateway = screenshotProtectionGateway,
       _secureKeyGateway = secureKeyGateway,
       _sessionController = sessionController,
       _pinStateController = pinStateController,
       _sessionKeyStore = sessionKeyStore,
       _logger = logger,
       _appIsForeground = appIsForeground;

  final BiometricGateway _biometricGateway;
  final ScreenshotProtectionGateway _screenshotProtectionGateway;
  final SecureKeyGateway _secureKeyGateway;
  final LockSessionController _sessionController;
  final PinStateController _pinStateController;
  final DatabaseSessionKeyStore _sessionKeyStore;
  final AppLogger _logger;
  final bool Function() _appIsForeground;

  Future<void> initialize() async {
    _sessionKeyStore.clear();
    await _screenshotProtectionGateway.enableSensitiveWindowProtection();
    await _secureKeyGateway.ensureRootKey();
    await _biometricGateway.getAvailability();
    _logger.info('security_initialized');
    _sessionController.lock();
  }

  Future<bool> unlockWithBiometrics() async {
    final expectedLockEpoch = _sessionController.lockEpoch;
    NativeUnlockResult? material;
    try {
      material = await _secureKeyGateway.unlockWithSystemAuth();
      return await _completeUnlock(
        UnlockMethod.biometric,
        expectedLockEpoch: expectedLockEpoch,
        material: material,
      );
    } finally {
      material?.clear();
    }
  }

  Future<bool> unlockWithPin({
    required String pin,
    required int expectedLockEpoch,
  }) async {
    NativeUnlockResult? material;
    try {
      material = await _secureKeyGateway.unlockWithPin(pin: pin);
      return await _completeUnlock(
        UnlockMethod.pin,
        expectedLockEpoch: expectedLockEpoch,
        material: material,
      );
    } finally {
      material?.clear();
    }
  }

  Future<NativeSecurityState> refreshSecurityState() async {
    final securityState = await _secureKeyGateway.getSecurityState();
    _syncPinConfigured(securityState.pinConfigured);
    return securityState;
  }

  Future<void> configurePin(String pin) async {
    await _secureKeyGateway.configurePin(pin: pin);
    _syncPinConfigured(true);
  }

  Future<void> removePin() async {
    await _secureKeyGateway.removePin();
    _syncPinConfigured(false);
  }

  Future<bool> _completeUnlock(
    UnlockMethod method, {
    required int expectedLockEpoch,
    NativeUnlockResult? material,
  }) async {
    if (!_canCompleteUnlock(expectedLockEpoch)) {
      return false;
    }

    if (material != null) {
      _sessionKeyStore.replace(
        DatabaseSessionKeys(
          databaseKey: material.databaseKey,
          fieldKey: material.fieldKey,
        ),
      );
    }

    try {
      await _screenshotProtectionGateway.updateRecentTaskProtection(
        obscured: false,
      );
    } catch (_) {
      _sessionKeyStore.clear();
      _sessionController.lock();
      return false;
    }

    if (!_canCompleteUnlock(expectedLockEpoch)) {
      _sessionKeyStore.clear();
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
    _syncPinConfigured(enabled);
  }

  void _syncPinConfigured(bool configured) {
    _sessionController.setPinEnabled(configured);
    _pinStateController.syncConfigured(configured);
  }
}
