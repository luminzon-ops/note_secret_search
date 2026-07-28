import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LegacyPinPreferenceStore {
  bool? getBool(String key);

  String? getString(String key);

  Future<bool> setBool(String key, bool value);

  Future<bool> remove(String key);
}

class SharedPreferencesLegacyPinMigrationStore
    implements LegacyPinMigrationStore {
  SharedPreferencesLegacyPinMigrationStore({
    required Future<SharedPreferences> Function() loadPreferences,
  }) : _loadPreferences = loadPreferences,
       _preferenceStore = null;

  const SharedPreferencesLegacyPinMigrationStore.withPreferenceStore(
    LegacyPinPreferenceStore preferenceStore,
  ) : _loadPreferences = null,
      _preferenceStore = preferenceStore;

  final Future<SharedPreferences> Function()? _loadPreferences;
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
    return _SharedPreferencesLegacyPinPreferenceStore(
      await _loadPreferences!(),
    );
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
