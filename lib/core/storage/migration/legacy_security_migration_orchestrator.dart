import 'dart:convert';
import 'dart:typed_data';

import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LegacyMigrationPostSwapValidator {
  Future<void> validate({
    required String activePath,
    required String databasePassword,
    required String keyId,
  });
}

class SqlCipherLegacyMigrationPostSwapValidator
    implements LegacyMigrationPostSwapValidator {
  const SqlCipherLegacyMigrationPostSwapValidator({
    required MigrationDatabaseFactory databaseFactory,
  }) : _databaseFactory = databaseFactory;

  final MigrationDatabaseFactory _databaseFactory;

  @override
  Future<void> validate({
    required String activePath,
    required String databasePassword,
    required String keyId,
  }) async {
    final database = await _databaseFactory.openLegacy(
      path: activePath,
      password: databasePassword,
    );
    try {
      final integrity = (await database.rawQuery('PRAGMA quick_check')).single;
      if (integrity.values.single.toString() != 'ok') {
        throw StateError('migration_post_swap_integrity_failed');
      }
      final metadata = await database.query(
        'security_metadata',
        columns: const <String>['key_id', 'migration_state'],
      );
      if (metadata.length != 1 ||
          metadata.single['key_id'] != keyId ||
          metadata.single['migration_state'] != 'validated') {
        throw StateError('migration_post_swap_metadata_failed');
      }
    } finally {
      await database.close();
    }
  }
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

abstract interface class LegacyPinPreferenceStore {
  bool? getBool(String key);

  String? getString(String key);

  Future<bool> setBool(String key, bool value);

  Future<bool> remove(String key);
}

class SharedPreferencesLegacyPinMigrationStore
    implements LegacyPinMigrationStore {
  const SharedPreferencesLegacyPinMigrationStore({
    Future<SharedPreferences> Function() preferences =
        SharedPreferences.getInstance,
  }) : _preferences = preferences,
       _preferenceStore = null;

  const SharedPreferencesLegacyPinMigrationStore.withPreferenceStore(
    LegacyPinPreferenceStore preferenceStore,
  ) : _preferences = null,
      _preferenceStore = preferenceStore;

  final Future<SharedPreferences> Function()? _preferences;
  final LegacyPinPreferenceStore? _preferenceStore;

  @override
  Future<LegacyPinMigrationMaterial> read() async {
    final preferences = await _loadPreferenceStore();
    final enabled = preferences.getBool(_enabledKey);
    final pin = preferences.getString(_materialKey);
    final cleanupPending = preferences.getBool(_cleanupPendingKey) == true;
    if (enabled == null && pin == null) {
      return const LegacyPinMigrationMaterial(enabled: false, pin: null);
    }
    if (enabled == true && pin != null && pin.isNotEmpty) {
      return LegacyPinMigrationMaterial(enabled: true, pin: pin);
    }
    if (cleanupPending && enabled == null && pin != null && pin.isNotEmpty) {
      return LegacyPinMigrationMaterial(enabled: true, pin: pin);
    }
    if (cleanupPending && pin == null) {
      return const LegacyPinMigrationMaterial(enabled: false, pin: null);
    }
    if (enabled == false && (pin == null || pin.isEmpty)) {
      return const LegacyPinMigrationMaterial(enabled: false, pin: null);
    }
    throw StateError('legacy_pin_state_inconsistent');
  }

  @override
  Future<void> clear() async {
    final preferences = await _loadPreferenceStore();
    final marked = await preferences.setBool(_cleanupPendingKey, true);
    if (!marked) {
      throw StateError('legacy_pin_cleanup_failed');
    }
    final removedEnabled = await preferences.remove(_enabledKey);
    if (!removedEnabled) {
      throw StateError('legacy_pin_cleanup_failed');
    }
    final removedMaterial = await preferences.remove(_materialKey);
    if (!removedMaterial) {
      throw StateError('legacy_pin_cleanup_failed');
    }
    final removedMarker = await preferences.remove(_cleanupPendingKey);
    if (!removedMarker) {
      throw StateError('legacy_pin_cleanup_failed');
    }
  }

  Future<LegacyPinPreferenceStore> _loadPreferenceStore() async {
    final injected = _preferenceStore;
    if (injected != null) {
      return injected;
    }
    return _SharedPreferencesLegacyPinPreferenceStore(await _preferences!());
  }

  static const _enabledKey = 'security.pin_enabled';
  static const _materialKey = 'security.pin_material';
  static const _cleanupPendingKey = 'security.pin_migration_cleanup_pending';
}

class _SharedPreferencesLegacyPinPreferenceStore
    implements LegacyPinPreferenceStore {
  const _SharedPreferencesLegacyPinPreferenceStore(this.preferences);

  final SharedPreferences preferences;

  @override
  bool? getBool(String key) => preferences.getBool(key);

  @override
  String? getString(String key) => preferences.getString(key);

  @override
  Future<bool> remove(String key) => preferences.remove(key);

  @override
  Future<bool> setBool(String key, bool value) =>
      preferences.setBool(key, value);
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
