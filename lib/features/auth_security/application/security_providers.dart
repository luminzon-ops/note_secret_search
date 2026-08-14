import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/logging/logging_providers.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/core/storage/migration/legacy_database_migrator.dart';
import 'package:note_secret_search/features/auth_security/application/app_bootstrap_service.dart';
import 'package:note_secret_search/features/auth_security/application/app_lock_lifecycle_controller.dart';
import 'package:note_secret_search/features/auth_security/application/legacy_security_migration.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_state.dart';
import 'package:note_secret_search/features/auth_security/domain/security_gateways.dart';

typedef AutoLockSecondsLoader = Future<int> Function();

final nativeSecurityBridgeProvider = Provider<NativeSecurityBridge>((ref) {
  throw StateError(
    'nativeSecurityBridgeProvider must be overridden by app composition',
  );
});

final nativeSecurityMigrationBridgeProvider =
    Provider<NativeSecurityMigrationBridge>((ref) {
      final bridge = ref.watch(nativeSecurityBridgeProvider);
      if (bridge is! NativeSecurityMigrationBridge) {
        throw StateError('Native migration bridge is unavailable.');
      }
      return bridge as NativeSecurityMigrationBridge;
    });

final legacyDatabaseMigrationRunnerProvider =
    Provider<LegacyDatabaseMigrationRunner>((ref) {
      throw StateError(
        'legacyDatabaseMigrationRunnerProvider must be overridden by '
        'app composition',
      );
    });

final legacyMigrationPostSwapValidatorProvider =
    Provider<LegacyMigrationPostSwapValidator>((ref) {
      throw StateError(
        'legacyMigrationPostSwapValidatorProvider must be overridden by '
        'app composition',
      );
    });

final legacyPinMigrationStoreProvider = Provider<LegacyPinMigrationStore>((
  ref,
) {
  throw StateError(
    'legacyPinMigrationStoreProvider must be overridden by app composition',
  );
});

final legacySecurityMigrationProvider = Provider<LegacySecurityMigrationRunner>(
  (ref) {
    return LegacySecurityMigrationOrchestrator(
      migrationBridge: ref.watch(nativeSecurityMigrationBridgeProvider),
      securityBridge: ref.watch(nativeSecurityBridgeProvider),
      migrationRunner: ref.watch(legacyDatabaseMigrationRunnerProvider),
      postSwapValidator: ref.watch(legacyMigrationPostSwapValidatorProvider),
      legacyPinStore: ref.watch(legacyPinMigrationStoreProvider),
      sessionKeyStore: ref.watch(databaseSessionKeyStoreProvider),
    );
  },
);

final biometricGatewayProvider = Provider<BiometricGateway>((ref) {
  throw StateError(
    'biometricGatewayProvider must be overridden by app composition',
  );
});

final screenshotProtectionGatewayProvider =
    Provider<ScreenshotProtectionGateway>((ref) {
      throw StateError(
        'screenshotProtectionGatewayProvider must be overridden by '
        'app composition',
      );
    });

final secureKeyGatewayProvider = Provider<SecureKeyGateway>((ref) {
  throw StateError(
    'secureKeyGatewayProvider must be overridden by app composition',
  );
});

final appUnlockVisibilityReaderProvider = Provider<AppUnlockVisibilityReader>((
  ref,
) {
  throw StateError(
    'appUnlockVisibilityReaderProvider must be overridden by app composition',
  );
});

final autoLockSecondsLoaderProvider = Provider<AutoLockSecondsLoader>((ref) {
  throw StateError(
    'autoLockSecondsLoaderProvider must be overridden by app composition',
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
    appUnlockVisibility: ref.watch(appUnlockVisibilityReaderProvider),
    legacySecurityMigration: ref.watch(legacySecurityMigrationProvider),
  );
});

final appLockLifecycleControllerProvider = Provider<AppLockLifecycleController>(
  (ref) {
    return AppLockLifecycleController(
      sessionController: ref.watch(lockSessionControllerProvider.notifier),
      autoLockSecondsLoader: ref.watch(autoLockSecondsLoaderProvider),
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
