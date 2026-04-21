import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/infrastructure/security_settings_repository.dart';
import 'package:note_secret_search/features/settings/infrastructure/shared_preferences_security_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

final securitySettingsRepositoryProvider = FutureProvider<SecuritySettingsRepository>((ref) async {
  final preferences = await ref.watch(sharedPreferencesProvider.future);
  return SharedPreferencesSecuritySettingsRepository(preferences: preferences);
});

final securitySettingsControllerProvider = StateNotifierProvider<SecuritySettingsController, AsyncValue<SecuritySettings>>((ref) {
  final repositoryAsync = ref.watch(securitySettingsRepositoryProvider);
  final repository = repositoryAsync.value;
  if (repository == null) {
    throw StateError('SecuritySettingsRepository is not ready');
  }

  return SecuritySettingsController(
    repository: repository,
    securityOrchestrator: ref.watch(securityOrchestratorProvider),
    pinStateController: ref.watch(pinStateControllerProvider.notifier),
  );
});
