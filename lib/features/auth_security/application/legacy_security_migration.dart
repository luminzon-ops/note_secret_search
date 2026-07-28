import 'dart:convert';
import 'dart:typed_data';

import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';

abstract interface class LegacyMigrationPostSwapValidator {
  Future<void> validate({
    required String activePath,
    required String databasePassword,
    required String keyId,
  });
}

class LegacyPinMigrationMaterial {
  const LegacyPinMigrationMaterial({required this.enabled, required this.pin});

  final bool enabled;
  final String? pin;
}

abstract interface class LegacyPinMigrationStore {
  Future<LegacyPinMigrationMaterial> read();

  Future<void> clear();
}

abstract interface class LegacySecurityMigrationRunner {
  Future<void> startOrResume();
}

class LegacySecurityMigrationOrchestrator
    implements LegacySecurityMigrationRunner {
  LegacySecurityMigrationOrchestrator({
    required NativeSecurityMigrationBridge migrationBridge,
    required NativeSecurityBridge securityBridge,
    required LegacyDatabaseMigrationRunner migrationRunner,
    required LegacyMigrationPostSwapValidator postSwapValidator,
    required LegacyPinMigrationStore legacyPinStore,
    required DatabaseSessionKeyStore sessionKeyStore,
  }) : _migrationBridge = migrationBridge,
       _securityBridge = securityBridge,
       _migrationRunner = migrationRunner,
       _postSwapValidator = postSwapValidator,
       _legacyPinStore = legacyPinStore,
       _sessionKeyStore = sessionKeyStore;

  final NativeSecurityMigrationBridge _migrationBridge;
  final NativeSecurityBridge _securityBridge;
  final LegacyDatabaseMigrationRunner _migrationRunner;
  final LegacyMigrationPostSwapValidator _postSwapValidator;
  final LegacyPinMigrationStore _legacyPinStore;
  final DatabaseSessionKeyStore _sessionKeyStore;

  @override
  Future<void> startOrResume() async {
    var state = await _migrationBridge.getLegacyMigrationState();
    final legacyPin = await _legacyPinStore.read();
    NativeUnlockResult? material;
    var abortOnFailure = false;
    try {
      if (state.stage != NativeLegacyMigrationStage.cleanupComplete) {
        material = await _migrationBridge.beginLegacyMigration();
        abortOnFailure = true;
        _sessionKeyStore.replace(
          DatabaseSessionKeys(
            databaseKey: material.databaseKey,
            fieldKey: material.fieldKey,
            keyId: material.keyId,
            searchIndexFingerprintKey: material.searchIndexFingerprintKey,
          ),
        );
        state = await _migrationBridge.getLegacyMigrationState();
        state = await _migrateDatabase(state, material);
      }
      await _finishCredentialMigration(state, legacyPin);
      abortOnFailure = false;
    } catch (_) {
      if (abortOnFailure) {
        await _abortQuietly();
      }
      rethrow;
    } finally {
      _sessionKeyStore.clear();
      material?.clear();
    }
  }

  Future<NativeLegacyMigrationState> _migrateDatabase(
    NativeLegacyMigrationState state,
    NativeUnlockResult material,
  ) async {
    final keyId = material.keyId;
    final databasePassword = _hex(material.databaseKey);
    final legacyPasswordBytes = material.legacyDatabasePassword;
    if (legacyPasswordBytes == null || legacyPasswordBytes.isEmpty) {
      throw StateError('legacy_database_password_missing');
    }
    final legacyPassword = utf8.decode(
      legacyPasswordBytes,
      allowMalformed: false,
    );

    if (state.stage == NativeLegacyMigrationStage.keyringReady) {
      await _migrationRunner.prepareSourceForBackup(
        sourcePath: state.activePath,
        legacyPassword: legacyPassword,
      );
      state = await _migrationBridge.prepareLegacyMigrationBackup(keyId);
    }
    if (_needsCopy(state.stage)) {
      state = await _migrationBridge.prepareLegacyMigrationPending(keyId);
      try {
        await _migrationRunner.migrate(
          sourcePath: state.sourcePath,
          pendingPath: state.pendingPath,
          legacyPassword: legacyPassword,
          databasePassword: databasePassword,
          keyId: keyId,
        );
      } catch (_) {
        await _resetPendingQuietly(keyId);
        rethrow;
      }
      state = await _migrationBridge.markLegacyMigrationRowsCopied(keyId);
      state = await _migrationBridge.markLegacyMigrationValidated(keyId);
    }
    if (state.stage == NativeLegacyMigrationStage.validated ||
        state.stage == NativeLegacyMigrationStage.oldMoved) {
      state = await _migrationBridge.activateLegacyMigration(keyId);
    }
    if (state.stage == NativeLegacyMigrationStage.newActivated) {
      try {
        await _postSwapValidator.validate(
          activePath: state.activePath,
          databasePassword: databasePassword,
          keyId: keyId,
        );
      } catch (_) {
        await _resetPendingQuietly(keyId);
        rethrow;
      }
      state = await _migrationBridge.markLegacyMigrationPostSwapValidated(
        keyId,
      );
    }
    if (state.stage == NativeLegacyMigrationStage.postSwapValidated) {
      state = await _migrationBridge.cleanupLegacyMigrationFiles(keyId);
    }
    if (state.stage != NativeLegacyMigrationStage.cleanupComplete) {
      throw StateError('legacy_migration_incomplete');
    }
    return state;
  }

  Future<void> _finishCredentialMigration(
    NativeLegacyMigrationState state,
    LegacyPinMigrationMaterial legacyPin,
  ) async {
    final keyId = state.keyId;
    final activeDigest = state.activeDigest;
    if (keyId == null || activeDigest == null) {
      throw StateError('legacy_migration_completion_missing');
    }
    if (legacyPin.enabled) {
      await _securityBridge.configurePin(pin: legacyPin.pin!);
    }
    await _legacyPinStore.clear();
    await _migrationBridge.commitLegacyMigration(
      keyId: keyId,
      activeDigest: activeDigest,
    );
    await _migrationBridge.finishLegacyMigration(keyId);
  }

  bool _needsCopy(NativeLegacyMigrationStage stage) {
    return stage == NativeLegacyMigrationStage.backupReady ||
        stage == NativeLegacyMigrationStage.pendingCreated ||
        stage == NativeLegacyMigrationStage.rowsCopied;
  }

  Future<void> _abortQuietly() async {
    try {
      await _migrationBridge.abortLegacyMigration();
    } catch (_) {
      // Durable journal and legacy credentials remain for the next resume.
    }
  }

  Future<void> _resetPendingQuietly(String keyId) async {
    try {
      await _migrationBridge.prepareLegacyMigrationPending(keyId);
    } catch (_) {
      // The journal and native workspace remain available for recovery.
    }
  }

  String _hex(Uint8List value) {
    return value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
