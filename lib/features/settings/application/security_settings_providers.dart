import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/auth_security/application/security_providers.dart';
import 'package:note_secret_search/features/settings/application/security_settings_controller.dart';
import 'package:note_secret_search/features/settings/domain/security_settings.dart';
import 'package:note_secret_search/features/settings/domain/security_settings_repository.dart';

final securitySettingsRepositoryProvider = Provider<SecuritySettingsRepository>(
  (ref) {
    throw StateError(
      'securitySettingsRepositoryProvider must be overridden by '
      'app composition',
    );
  },
);

final securitySettingsControllerProvider =
    StateNotifierProvider<
      SecuritySettingsController,
      AsyncValue<SecuritySettings>
    >((ref) {
      return SecuritySettingsController(
        repository: ref.watch(securitySettingsRepositoryProvider),
        securityOrchestrator: ref.watch(securityOrchestratorProvider),
        pinStateController: ref.watch(pinStateControllerProvider.notifier),
      );
    });
