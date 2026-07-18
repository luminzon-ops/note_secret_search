import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/migration/legacy_security_migration_orchestrator.dart';
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
    required AppDatabase database,
    required AppLogger logger,
    required bool Function() appIsForeground,
    LegacySecurityMigrationRunner? legacySecurityMigration,
  }) : _screenshotProtectionGateway = screenshotProtectionGateway,
       _secureKeyGateway = secureKeyGateway,
       _sessionController = sessionController,
       _pinStateController = pinStateController,
       _sessionKeyStore = sessionKeyStore,
       _database = database,
       _logger = logger,
       _appIsForeground = appIsForeground,
       _legacySecurityMigration = legacySecurityMigration;

  final ScreenshotProtectionGateway _screenshotProtectionGateway;
  final SecureKeyGateway _secureKeyGateway;
  final LockSessionController _sessionController;
  final PinStateController _pinStateController;
  final DatabaseSessionKeyStore _sessionKeyStore;
  final AppDatabase _database;
  final AppLogger _logger;
  final bool Function() _appIsForeground;
  final LegacySecurityMigrationRunner? _legacySecurityMigration;
  int _operationEpoch = 0;
  bool _unlockInProgress = false;

  Future<void> initialize() async {
    _sessionKeyStore.clear();
    await _screenshotProtectionGateway.enableSensitiveWindowProtection();
    final securityState = await _secureKeyGateway.getSecurityState();
    _syncPinConfigured(securityState.pinConfigured);
    _logger.info('security_initialized');
    _sessionController.lock();
  }

  Future<NativeSecurityState> migrateLegacySecurity() async {
    if (_sessionController.isUnlocked ||
        _database.state.status != DatabaseLifecycleStatus.locked) {
      throw StateError('legacy_security_migration_requires_locked_database');
    }
    final migration = _legacySecurityMigration;
    if (migration == null) {
      throw StateError('legacy_security_migration_unavailable');
    }
    _sessionKeyStore.clear();
    try {
      await migration.startOrResume();
      return await refreshSecurityState();
    } finally {
      _sessionKeyStore.clear();
    }
  }

  Future<bool> unlockWithBiometrics() {
    return _runUnlockOperation(() async {
      final expectedLockEpoch = _sessionController.lockEpoch;
      final expectedOperationEpoch = _operationEpoch;
      NativeUnlockResult? material;
      try {
        material = await _secureKeyGateway.unlockWithSystemAuth();
        return await _completeUnlock(
          UnlockMethod.biometric,
          expectedLockEpoch: expectedLockEpoch,
          expectedOperationEpoch: expectedOperationEpoch,
          material: material,
        );
      } finally {
        material?.clear();
      }
    });
  }

  Future<bool> provisionWithSystemAuth() {
    return _runUnlockOperation(() async {
      final expectedLockEpoch = _sessionController.lockEpoch;
      final expectedOperationEpoch = _operationEpoch;
      NativeUnlockResult? material;
      try {
        material = await _secureKeyGateway.provisionWithSystemAuth();
        return await _completeUnlock(
          UnlockMethod.biometric,
          expectedLockEpoch: expectedLockEpoch,
          expectedOperationEpoch: expectedOperationEpoch,
          material: material,
        );
      } finally {
        material?.clear();
      }
    });
  }

  Future<bool> unlockWithPin({
    required String pin,
    required int expectedLockEpoch,
  }) {
    return _runUnlockOperation(() async {
      final expectedOperationEpoch = _operationEpoch;
      NativeSecurityState? securityState;
      NativeUnlockResult? material;
      try {
        try {
          securityState = await _secureKeyGateway.getSecurityState();
        } catch (_) {
          securityState = null;
        }
        material = await _secureKeyGateway.unlockWithPin(pin: pin);
        if (securityState?.systemRebindRequired == true) {
          try {
            await _secureKeyGateway.rebindSystemAuthWithPin(pin: pin);
          } catch (_) {
            // The valid PIN unlock remains usable and rebind can be retried.
          }
        }
        return await _completeUnlock(
          UnlockMethod.pin,
          expectedLockEpoch: expectedLockEpoch,
          expectedOperationEpoch: expectedOperationEpoch,
          material: material,
        );
      } finally {
        material?.clear();
      }
    });
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

  Future<void> lock() async {
    _operationEpoch += 1;
    try {
      await _screenshotProtectionGateway.updateRecentTaskProtection(
        obscured: true,
      );
    } catch (_) {
      // Database access is still revoked when platform shielding fails.
    }

    final closing = _database.close();
    _sessionController.lock();
    try {
      await closing;
    } catch (_) {
      // The database remains access-revoked and close can be retried.
    } finally {
      _sessionKeyStore.clear();
    }
  }

  Future<bool> _completeUnlock(
    UnlockMethod method, {
    required int expectedLockEpoch,
    required int expectedOperationEpoch,
    NativeUnlockResult? material,
  }) async {
    if (!_canCompleteUnlock(expectedLockEpoch, expectedOperationEpoch)) {
      return false;
    }

    if (material == null) {
      return false;
    }

    final sessionKeys = DatabaseSessionKeys(
      databaseKey: material.databaseKey,
      fieldKey: material.fieldKey,
    );
    _sessionKeyStore.replace(sessionKeys);
    try {
      await _database.open(sessionKeys);
    } on DatabaseLifecycleException {
      await _revokeFailedUnlock();
      rethrow;
    } catch (_) {
      await _revokeFailedUnlock();
      return false;
    }

    if (!_canCompleteUnlock(expectedLockEpoch, expectedOperationEpoch)) {
      await _revokeFailedUnlock();
      return false;
    }

    try {
      await _screenshotProtectionGateway.updateRecentTaskProtection(
        obscured: false,
      );
    } catch (_) {
      await _revokeFailedUnlock();
      return false;
    }

    if (!_canCompleteUnlock(expectedLockEpoch, expectedOperationEpoch)) {
      await _revokeFailedUnlock();
      await _restoreShieldAfterStaleUnlock();
      return false;
    }

    _sessionController.markUnlocked(method);
    _pinStateController.resetFailures();
    return true;
  }

  Future<void> _revokeFailedUnlock() async {
    final closing = _database.close();
    _sessionController.lock();
    try {
      await closing;
    } catch (_) {
      // Access was revoked synchronously even if the native close needs retry.
    } finally {
      _sessionKeyStore.clear();
    }
  }

  Future<bool> _runUnlockOperation(Future<bool> Function() operation) async {
    if (_unlockInProgress) {
      return false;
    }
    _unlockInProgress = true;
    try {
      return await operation();
    } finally {
      _unlockInProgress = false;
    }
  }

  bool _canCompleteUnlock(int expectedLockEpoch, int expectedOperationEpoch) {
    return !_sessionController.isUnlocked &&
        _sessionController.lockEpoch == expectedLockEpoch &&
        _operationEpoch == expectedOperationEpoch &&
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
