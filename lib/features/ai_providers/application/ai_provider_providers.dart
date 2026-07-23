import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_providers/application/external_chat_gateway.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/openai_compatible_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/ollama_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/infrastructure/sqlite_external_provider_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
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

final externalProviderClientRouterProvider = Provider<ExternalProviderClient>((
  ref,
) {
  return _ExternalProviderClientRouter(
    openAiCompatible: OpenAiCompatibleProviderClient(dio: Dio()),
    ollama: OllamaProviderClient(dio: Dio()),
  );
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

final externalProviderConfigsProvider =
    FutureProvider<List<ExternalProviderConfig>>((ref) {
      return guardSensitiveFuture<List<ExternalProviderConfig>>(
        ref,
        lockedValue: const <ExternalProviderConfig>[],
        load: () => ref.watch(externalProviderRepositoryProvider).loadAll(),
      );
    });

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
      final configuration = await ref.watch(searchConfigurationProvider.future);
      if (!configuration.allowExternalProviderAccess) {
        return ExternalProviderStatus(
          available: false,
          reason: '尚未允许外部 AI 访问。',
          config: config,
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

final externalChatGatewayProvider = Provider<ExternalChatGateway>((ref) {
  final confirmation = ref.watch(externalPrivacyConfirmationControllerProvider);
  final gateway = ExternalChatGateway(
    repository: ref.watch(externalProviderRepositoryProvider),
    clientFor: (_) => ref.read(externalProviderClientRouterProvider),
    hasConsent: (config, scope) {
      return confirmation.hasAcknowledged(
        config,
        includesPrivateContext:
            scope == ExternalProviderConsentScope.privateContext,
      );
    },
    isExternalAccessAllowed: () async {
      final configuration = await ref.read(searchConfigurationProvider.future);
      return configuration.allowExternalProviderAccess;
    },
  );
  ref.listen<AsyncValue<SearchConfiguration>>(
    searchConfigurationProvider,
    (_, next) {
      final configuration = next.valueOrNull;
      if (configuration != null &&
          !configuration.allowExternalProviderAccess) {
        gateway.cancelAll();
      }
    },
  );
  ref.onDispose(gateway.cancelAll);
  return gateway;
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
    await revokeScope(config, scope: ExternalProviderConsentScope.standard);
    await revokeScope(
      config,
      scope: ExternalProviderConsentScope.privateContext,
    );
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    await preferences.remove(
      'ai.external_privacy_ack.v2.'
      '${externalProviderConsentFingerprint(config)}',
    );
  }

  Future<void> revokeScope(
    ExternalProviderConfig config, {
    required ExternalProviderConsentScope scope,
  }) async {
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    await preferences.remove(_providerAcknowledgementKey(config, scope: scope));
  }

  String _providerAcknowledgementKey(
    ExternalProviderConfig config, {
    ExternalProviderConsentScope? scope,
    bool? includesPrivateContext,
  }) {
    final resolvedScope =
        scope ??
        (includesPrivateContext == true
            ? ExternalProviderConsentScope.privateContext
            : ExternalProviderConsentScope.standard);
    return 'ai.external_privacy_ack.v4.${resolvedScope.name}.'
        '${externalProviderConsentFingerprint(config, scope: resolvedScope)}';
  }
}

class ExternalProviderSettingsController {
  ExternalProviderSettingsController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> save(ExternalProviderConfig config) async {
    final repository = _ref.read(externalProviderRepositoryProvider);
    final existing = await repository.loadById(config.id);
    if (existing != null) {
      await _invalidateChangedConsent(existing: existing, updated: config);
    }
    final previouslyEnabled = await repository.loadEnabled();
    if (config.enabled &&
        previouslyEnabled != null &&
        previouslyEnabled.id != config.id) {
      await _ref
          .read(externalPrivacyConfirmationControllerProvider)
          .revoke(previouslyEnabled);
      _ref
          .read(externalChatGatewayProvider)
          .invalidateConfiguration(previouslyEnabled.id);
    }
    await repository.save(config);
    if (existing?.enabled == true && !config.enabled) {
      _ref.read(externalChatGatewayProvider).invalidateConfiguration(config.id);
    }
    _invalidateProviderState();
  }

  Future<void> setEnabled(
    ExternalProviderConfig config, {
    required bool enabled,
  }) async {
    final repository = _ref.read(externalProviderRepositoryProvider);
    final persisted = await repository.loadById(config.id) ?? config;
    await save(persisted.copyWith(enabled: enabled));
  }

  Future<void> revokeConsent(ExternalProviderConfig config) async {
    final repository = _ref.read(externalProviderRepositoryProvider);
    final persisted = await repository.loadById(config.id) ?? config;
    await _ref
        .read(externalPrivacyConfirmationControllerProvider)
        .revoke(persisted);
    _ref
        .read(externalChatGatewayProvider)
        .invalidateConfiguration(persisted.id);
  }

  Future<void> _invalidateChangedConsent({
    required ExternalProviderConfig existing,
    required ExternalProviderConfig updated,
  }) async {
    final confirmation = _ref.read(
      externalPrivacyConfirmationControllerProvider,
    );
    final gateway = _ref.read(externalChatGatewayProvider);
    final oldStandard = externalProviderConsentFingerprint(
      existing,
      scope: ExternalProviderConsentScope.standard,
    );
    final newStandard = externalProviderConsentFingerprint(
      updated,
      scope: ExternalProviderConsentScope.standard,
    );
    if (oldStandard != newStandard) {
      await confirmation.revoke(existing);
      gateway.invalidateConfiguration(existing.id);
      return;
    }

    final oldPrivate = externalProviderConsentFingerprint(
      existing,
      scope: ExternalProviderConsentScope.privateContext,
    );
    final newPrivate = externalProviderConsentFingerprint(
      updated,
      scope: ExternalProviderConsentScope.privateContext,
    );
    if (oldPrivate != newPrivate) {
      await confirmation.revokeScope(
        existing,
        scope: ExternalProviderConsentScope.privateContext,
      );
      gateway.invalidateFingerprint(oldPrivate);
    }
  }

  void _invalidateProviderState() {
    _ref.invalidate(enabledExternalProviderProvider);
    _ref.invalidate(externalProviderConfigsProvider);
    _ref.invalidate(externalProviderStatusProvider);
    _ref.invalidate(externalProviderClientProvider);
  }

  Future<void> testConnection(ExternalProviderConfig config) async {
    await _ref
        .read(externalProviderClientRouterProvider)
        .testConnection(config);
  }
}

class _ExternalProviderClientRouter
    implements ExternalProviderClient, CancellableExternalProviderClient {
  _ExternalProviderClientRouter({
    required ExternalProviderClient openAiCompatible,
    required ExternalProviderClient ollama,
  }) : _openAiCompatible = openAiCompatible,
       _ollama = ollama;

  final ExternalProviderClient _openAiCompatible;
  final ExternalProviderClient _ollama;
  final Map<String, ExternalProviderClient> _requestClients =
      <String, ExternalProviderClient>{};

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) {
    return _for(config).generateChatCompletion(
      config: config,
      prompt: prompt,
      usedPrivateContext: usedPrivateContext,
    );
  }

  @override
  Future<String> generateCancellableChatCompletion({
    required String requestId,
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    final client = _for(config);
    _requestClients[requestId] = client;
    try {
      if (client is CancellableExternalProviderClient) {
        return (client as CancellableExternalProviderClient)
            .generateCancellableChatCompletion(
              requestId: requestId,
              config: config,
              prompt: prompt,
              usedPrivateContext: usedPrivateContext,
            );
      }
      return client.generateChatCompletion(
        config: config,
        prompt: prompt,
        usedPrivateContext: usedPrivateContext,
      );
    } finally {
      if (identical(_requestClients[requestId], client)) {
        _requestClients.remove(requestId);
      }
    }
  }

  @override
  void cancelRequest(String requestId) {
    final client = _requestClients[requestId];
    if (client is CancellableExternalProviderClient) {
      (client as CancellableExternalProviderClient).cancelRequest(requestId);
    }
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) {
    return _for(config).testConnection(config);
  }

  ExternalProviderClient _for(ExternalProviderConfig config) {
    return switch (config.providerType) {
      ExternalProviderType.openAiCompatible => _openAiCompatible,
      ExternalProviderType.ollama => _ollama,
    };
  }
}
