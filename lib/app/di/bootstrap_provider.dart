import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/sqlcipher_database.dart';
import 'package:note_secret_search/features/auth_security/application/app_bootstrap_service.dart';
import 'package:note_secret_search/features/auth_security/application/app_lock_lifecycle_controller.dart';
import 'package:note_secret_search/features/auth_security/application/pin_state_controller.dart';
import 'package:note_secret_search/features/auth_security/application/security_orchestrator.dart';
import 'package:note_secret_search/features/auth_security/domain/pin_state.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/database_key_provider.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

final loggerProvider = Provider<AppLogger>((ref) => const AppLogger());

final cryptoServiceProvider = Provider<CryptoService>((ref) => const MvpCryptoService());

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return SqlCipherAppDatabase(
    logger: ref.watch(loggerProvider),
    databaseKeyProvider: ref.watch(databaseKeyProvider),
  );
});

final nativeSecurityBridgeProvider = Provider<NativeSecurityBridge>((ref) {
  return const MethodChannelNativeSecurityBridge();
});

final biometricGatewayProvider = Provider<BiometricGateway>((ref) {
  return DeviceBiometricGateway(bridge: ref.watch(nativeSecurityBridgeProvider));
});

final screenshotProtectionGatewayProvider = Provider<ScreenshotProtectionGateway>((ref) {
  return DeviceScreenshotProtectionGateway(
    bridge: ref.watch(nativeSecurityBridgeProvider),
  );
});

final secureKeyGatewayProvider = Provider<SecureKeyGateway>((ref) {
  return DeviceSecureKeyGateway(bridge: ref.watch(nativeSecurityBridgeProvider));
});

final databaseKeyProvider = Provider<DatabaseKeyProvider>((ref) {
  return NativeDatabaseKeyProvider(
    secureKeyGateway: ref.watch(secureKeyGatewayProvider),
  );
});

final lockSessionControllerProvider = StateNotifierProvider<LockSessionController, LockSessionState>(
  (ref) => LockSessionController(),
);

final pinStateControllerProvider = StateNotifierProvider<PinStateController, PinState>(
  (ref) => PinStateController(),
);

final securityOrchestratorProvider = Provider<SecurityOrchestrator>((ref) {
  return SecurityOrchestrator(
    biometricGateway: ref.watch(biometricGatewayProvider),
    screenshotProtectionGateway: ref.watch(screenshotProtectionGatewayProvider),
    secureKeyGateway: ref.watch(secureKeyGatewayProvider),
    sessionController: ref.watch(lockSessionControllerProvider.notifier),
    pinStateController: ref.watch(pinStateControllerProvider.notifier),
    logger: ref.watch(loggerProvider),
  );
});

final appLockLifecycleControllerProvider = Provider<AppLockLifecycleController>((ref) {
  return AppLockLifecycleController(
    sessionController: ref.watch(lockSessionControllerProvider.notifier),
    autoLockSecondsLoader: () async {
      final repository = await ref.read(securitySettingsRepositoryProvider.future);
      return repository.loadAutoLockSeconds();
    },
    screenshotProtectionGateway: ref.watch(screenshotProtectionGatewayProvider),
  );
});

final appBootstrapServiceProvider = Provider<AppBootstrapService>((ref) {
  return AppBootstrapService(
    database: ref.watch(appDatabaseProvider),
    securityOrchestrator: ref.watch(securityOrchestratorProvider),
    logger: ref.watch(loggerProvider),
  );
});

final appBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.watch(appBootstrapServiceProvider).bootstrap();
});
