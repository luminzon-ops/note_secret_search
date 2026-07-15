import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/openai_compatible_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/ollama_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/sqlite_external_provider_repository.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

final externalProviderRepositoryProvider = Provider<ExternalProviderRepository>(
  (ref) {
    return SqliteExternalProviderRepository(
      database: ref.watch(appDatabaseProvider),
      cryptoService: ref.watch(cryptoServiceProvider),
    );
  },
);

final externalProviderClientProvider = Provider<ExternalProviderClient>((ref) {
  final dio = Dio();
  final configAsync = ref.watch(enabledExternalProviderProvider);
  final config = configAsync.valueOrNull;
  if (config != null && config.providerType == ExternalProviderType.ollama) {
    return OllamaProviderClient(dio: dio);
  }
  return OpenAiCompatibleProviderClient(dio: dio);
});

final enabledExternalProviderProvider = FutureProvider<ExternalProviderConfig?>(
  (ref) {
    return guardSensitiveFuture<ExternalProviderConfig?>(
      ref,
      lockedValue: null,
      load: () => ref.watch(externalProviderRepositoryProvider).loadEnabled(),
    );
  },
);

final externalProviderStatusProvider = FutureProvider<ExternalProviderStatus>((
  ref,
) {
  return guardSensitiveFuture<ExternalProviderStatus>(
    ref,
    lockedValue: const ExternalProviderStatus(
      available: false,
      reason: '应用已锁定。',
      config: null,
    ),
    load: () async {
      final config = await ref.watch(enabledExternalProviderProvider.future);
      if (config == null) {
        return const ExternalProviderStatus(
          available: false,
          reason: '尚未启用外部模型提供方。',
          config: null,
        );
      }
      return ExternalProviderStatus(
        available: true,
        reason: '外部模型已可用：${config.displayName}',
        config: config,
      );
    },
  );
});

final externalPrivacyConfirmationControllerProvider =
    Provider<ExternalPrivacyConfirmationController>((ref) {
      return ExternalPrivacyConfirmationController(ref: ref);
    });

final externalProviderSettingsControllerProvider =
    Provider<ExternalProviderSettingsController>((ref) {
      return ExternalProviderSettingsController(ref: ref);
    });

class ExternalProviderStatus {
  const ExternalProviderStatus({
    required this.available,
    required this.reason,
    required this.config,
  });

  final bool available;
  final String reason;
  final ExternalProviderConfig? config;
}

class ExternalPrivacyConfirmationController {
  ExternalPrivacyConfirmationController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<bool> hasAcknowledged(
    ExternalProviderConfig config, {
    required bool includesPrivateContext,
  }) async {
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    return preferences.getBool(
          _providerAcknowledgementKey(
            config,
            includesPrivateContext: includesPrivateContext,
          ),
        ) ??
        false;
  }

  Future<void> markAcknowledged(
    ExternalProviderConfig config, {
    required bool includesPrivateContext,
  }) async {
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    await preferences.setBool(
      _providerAcknowledgementKey(
        config,
        includesPrivateContext: includesPrivateContext,
      ),
      true,
    );
  }

  Future<void> revoke(ExternalProviderConfig config) async {
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    await preferences.remove(
      _providerAcknowledgementKey(config, includesPrivateContext: false),
    );
    await preferences.remove(
      _providerAcknowledgementKey(config, includesPrivateContext: true),
    );
    await preferences.remove(
      'ai.external_privacy_ack.v2.'
      '${externalProviderConsentFingerprint(config)}',
    );
  }

  String _providerAcknowledgementKey(
    ExternalProviderConfig config, {
    required bool includesPrivateContext,
  }) {
    final contextScope = includesPrivateContext ? 'private' : 'standard';
    return 'ai.external_privacy_ack.v3.$contextScope.'
        '${externalProviderConsentFingerprint(config)}';
  }
}

class ExternalProviderSettingsController {
  ExternalProviderSettingsController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> save(ExternalProviderConfig config) async {
    final repository = _ref.read(externalProviderRepositoryProvider);
    final existing = await repository.loadById(config.id);
    if (existing != null) {
      await _ref
          .read(externalPrivacyConfirmationControllerProvider)
          .revoke(existing);
    }
    await repository.save(config);
    _ref.invalidate(enabledExternalProviderProvider);
    _ref.invalidate(externalProviderStatusProvider);
  }

  Future<void> testConnection(ExternalProviderConfig config) async {
    await _ref.read(externalProviderClientProvider).testConnection(config);
  }
}
