import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/composition/shared_preferences_composition.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/core/storage/migration/sqlcipher_migration_database_factory.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/shared_preferences_legacy_pin_migration_store.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/sqlcipher_legacy_migration_post_swap_validator.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/settings/infrastructure/shared_preferences_security_settings_repository.dart';

final List<Override> securityCompositionOverrides = <Override>[
  nativeSecurityBridgeProvider.overrideWith((ref) {
    return const MethodChannelNativeSecurityBridge();
  }),
  legacyDatabaseMigrationRunnerProvider.overrideWith((ref) {
    return LegacyDatabaseMigrator(
      databaseFactory: const SqlCipherMigrationDatabaseFactory(),
      cryptoService: ref.watch(cryptoServiceProvider),
    );
  }),
  legacyMigrationPostSwapValidatorProvider.overrideWith((ref) {
    return const SqlCipherLegacyMigrationPostSwapValidator(
      databaseFactory: SqlCipherMigrationDatabaseFactory(),
    );
  }),
  legacyPinMigrationStoreProvider.overrideWith((ref) {
    return SharedPreferencesLegacyPinMigrationStore(
      loadPreferences: () => ref.read(sharedPreferencesProvider.future),
    );
  }),
  biometricGatewayProvider.overrideWith((ref) {
    return DeviceBiometricGateway(
      bridge: ref.watch(nativeSecurityBridgeProvider),
    );
  }),
  screenshotProtectionGatewayProvider.overrideWith((ref) {
    return DeviceScreenshotProtectionGateway(
      bridge: ref.watch(nativeSecurityBridgeProvider),
    );
  }),
  secureKeyGatewayProvider.overrideWith((ref) {
    return DeviceSecureKeyGateway(
      bridge: ref.watch(nativeSecurityBridgeProvider),
    );
  }),
  appForegroundReaderProvider.overrideWithValue(() {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    return lifecycleState == null ||
        lifecycleState == AppLifecycleState.resumed;
  }),
  securitySettingsRepositoryProvider.overrideWith((ref) {
    return SharedPreferencesSecuritySettingsRepository(
      loadPreferences: () => ref.read(sharedPreferencesProvider.future),
    );
  }),
  autoLockSecondsLoaderProvider.overrideWith((ref) {
    final repository = ref.watch(securitySettingsRepositoryProvider);
    return repository.loadAutoLockSeconds;
  }),
];
