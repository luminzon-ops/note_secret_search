import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/sqlcipher_database.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/core/storage/migration/legacy_security_migration_orchestrator.dart';
import 'package:note_secret_search/core/storage/migration/sqlcipher_migration_database_factory.dart';
import 'package:note_secret_search/features/auth_security/application/app_bootstrap_service.dart';
import 'package:note_secret_search/features/auth_security/application/app_lock_lifecycle_controller.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_state.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

final loggerProvider = Provider<AppLogger>((ref) => const AppLogger());

final databaseSessionKeyStoreProvider = Provider<DatabaseSessionKeyStore>((
  ref,
) {
  final store = DatabaseSessionKeyStore();
  ref.onDispose(store.clear);
  return store;
});

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return AesGcmFieldCrypto(
    sessionKeyStore: ref.watch(databaseSessionKeyStoreProvider),
  );
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = SqlCipherAppDatabase(logger: ref.watch(loggerProvider));
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final appDatabaseLifecycleProvider = StreamProvider<DatabaseLifecycleState>((
  ref,
) async* {
  final database = ref.watch(appDatabaseProvider);
  yield database.state;
  yield* database.states;
});

final nativeSecurityBridgeProvider = Provider<NativeSecurityBridge>((ref) {
  return const MethodChannelNativeSecurityBridge();
});

final nativeSecurityMigrationBridgeProvider =
    Provider<NativeSecurityMigrationBridge>((ref) {
      final bridge = ref.watch(nativeSecurityBridgeProvider);
      if (bridge is! NativeSecurityMigrationBridge) {
        throw StateError('Native migration bridge is unavailable.');
      }
      return bridge as NativeSecurityMigrationBridge;
    });

final migrationDatabaseFactoryProvider = Provider<MigrationDatabaseFactory>((
  ref,
) {
  return const SqlCipherMigrationDatabaseFactory();
});

final legacyDatabaseMigratorProvider = Provider<LegacyDatabaseMigrationRunner>((
  ref,
) {
  return LegacyDatabaseMigrator(
    databaseFactory: ref.watch(migrationDatabaseFactoryProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
  );
});

final legacyMigrationPostSwapValidatorProvider =
    Provider<LegacyMigrationPostSwapValidator>((ref) {
      return SqlCipherLegacyMigrationPostSwapValidator(
        databaseFactory: ref.watch(migrationDatabaseFactoryProvider),
      );
    });

final legacyPinMigrationStoreProvider = Provider<LegacyPinMigrationStore>((
  ref,
) {
  return const SharedPreferencesLegacyPinMigrationStore();
});

final legacySecurityMigrationProvider = Provider<LegacySecurityMigrationRunner>(
  (ref) {
    return LegacySecurityMigrationOrchestrator(
      migrationBridge: ref.watch(nativeSecurityMigrationBridgeProvider),
      securityBridge: ref.watch(nativeSecurityBridgeProvider),
      migrationRunner: ref.watch(legacyDatabaseMigratorProvider),
      postSwapValidator: ref.watch(legacyMigrationPostSwapValidatorProvider),
      legacyPinStore: ref.watch(legacyPinMigrationStoreProvider),
      sessionKeyStore: ref.watch(databaseSessionKeyStoreProvider),
    );
  },
);

final biometricGatewayProvider = Provider<BiometricGateway>((ref) {
  return DeviceBiometricGateway(
    bridge: ref.watch(nativeSecurityBridgeProvider),
  );
});

final screenshotProtectionGatewayProvider =
    Provider<ScreenshotProtectionGateway>((ref) {
      return DeviceScreenshotProtectionGateway(
        bridge: ref.watch(nativeSecurityBridgeProvider),
      );
    });

final secureKeyGatewayProvider = Provider<SecureKeyGateway>((ref) {
  return DeviceSecureKeyGateway(
    bridge: ref.watch(nativeSecurityBridgeProvider),
  );
});

final lockSessionControllerProvider =
    StateNotifierProvider<LockSessionController, LockSessionState>((ref) {
      final nativeSecurityBridge = ref.watch(nativeSecurityBridgeProvider);
      return LockSessionController(
        onLock: () {
          unawaited(_cancelNativeSecurityOperation(nativeSecurityBridge));
        },
      );
    });

Future<void> _cancelNativeSecurityOperation(
  NativeSecurityBridge nativeSecurityBridge,
) async {
  try {
    await nativeSecurityBridge.lock();
  } catch (_) {
    // Dart-side access is already revoked; native lock can retry later.
  }
}

final sensitiveStateAccessAllowedProvider = StateProvider<bool>((ref) => false);

FutureOr<T> guardSensitiveFuture<T>(
  Ref ref, {
  required T lockedValue,
  required Future<T> Function() load,
}) {
  if (!ref.watch(sensitiveStateAccessAllowedProvider)) {
    return lockedValue;
  }
  return load();
}

final pinStateControllerProvider =
    StateNotifierProvider<PinStateController, PinState>(
      (ref) => PinStateController(),
    );

final securityOrchestratorProvider = Provider<SecurityOrchestrator>((ref) {
  return SecurityOrchestrator(
    biometricGateway: ref.watch(biometricGatewayProvider),
    screenshotProtectionGateway: ref.watch(screenshotProtectionGatewayProvider),
    secureKeyGateway: ref.watch(secureKeyGatewayProvider),
    sessionController: ref.watch(lockSessionControllerProvider.notifier),
    pinStateController: ref.watch(pinStateControllerProvider.notifier),
    sessionKeyStore: ref.watch(databaseSessionKeyStoreProvider),
    database: ref.watch(appDatabaseProvider),
    logger: ref.watch(loggerProvider),
    appIsForeground: () {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      return lifecycleState == null ||
          lifecycleState == AppLifecycleState.resumed;
    },
    legacySecurityMigration: ref.watch(legacySecurityMigrationProvider),
  );
});

final appLockLifecycleControllerProvider = Provider<AppLockLifecycleController>(
  (ref) {
    return AppLockLifecycleController(
      sessionController: ref.watch(lockSessionControllerProvider.notifier),
      autoLockSecondsLoader: () async {
        final repository = await ref.read(
          securitySettingsRepositoryProvider.future,
        );
        return repository.loadAutoLockSeconds();
      },
      screenshotProtectionGateway: ref.watch(
        screenshotProtectionGatewayProvider,
      ),
      lockApplication: ref.watch(securityOrchestratorProvider).lock,
    );
  },
);

final appBootstrapServiceProvider = Provider<AppBootstrapService>((ref) {
  return AppBootstrapService(
    securityOrchestrator: ref.watch(securityOrchestratorProvider),
    logger: ref.watch(loggerProvider),
  );
});

final appBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.watch(appBootstrapServiceProvider).bootstrap();
});
