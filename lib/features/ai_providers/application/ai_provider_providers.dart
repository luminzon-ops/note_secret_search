import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/external_chat_gateway.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent_store.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';

final externalProviderRepositoryProvider = Provider<ExternalProviderRepository>((
  ref,
) {
  throw StateError(
    'externalProviderRepositoryProvider must be overridden by app composition',
  );
});

final externalProviderClientRouterProvider = Provider<ExternalProviderClient>((
  ref,
) {
  throw StateError(
    'externalProviderClientRouterProvider must be overridden by app composition',
  );
});

final externalProviderConsentStoreProvider =
    Provider<ExternalProviderConsentStore>((ref) {
      throw StateError(
        'externalProviderConsentStoreProvider must be overridden by app composition',
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
      return ExternalPrivacyConfirmationController(
        store: ref.watch(externalProviderConsentStoreProvider),
      );
    });

final externalProviderSettingsControllerProvider =
    Provider<ExternalProviderSettingsController>((ref) {
      return ExternalProviderSettingsController(
        repository: ref.watch(externalProviderRepositoryProvider),
        confirmation: ref.watch(externalPrivacyConfirmationControllerProvider),
        gateway: ref.watch(externalChatGatewayProvider),
        testConnection: (config) => ref
            .read(externalProviderClientRouterProvider)
            .testConnection(config),
        invalidateProviderState: () {
          ref.invalidate(enabledExternalProviderProvider);
          ref.invalidate(externalProviderConfigsProvider);
          ref.invalidate(externalProviderStatusProvider);
          ref.invalidate(externalProviderClientRouterProvider);
        },
      );
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
  ref.listen<AsyncValue<SearchConfiguration>>(searchConfigurationProvider, (
    _,
    next,
  ) {
    final configuration = next.valueOrNull;
    if (configuration != null && !configuration.allowExternalProviderAccess) {
      gateway.cancelAll();
    }
  });
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
  ExternalPrivacyConfirmationController({
    required ExternalProviderConsentStore store,
  }) : _store = store;

  final ExternalProviderConsentStore _store;

  Future<bool> hasAcknowledged(
    ExternalProviderConfig config, {
    required bool includesPrivateContext,
  }) async {
    return _store.read(
      _providerAcknowledgementKey(
        config,
        includesPrivateContext: includesPrivateContext,
      ),
    );
  }

  Future<void> markAcknowledged(
    ExternalProviderConfig config, {
    required bool includesPrivateContext,
  }) async {
    await _store.write(
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
    await _store.remove(
      'ai.external_privacy_ack.v2.'
      '${externalProviderConsentFingerprint(config)}',
    );
  }

  Future<void> revokeScope(
    ExternalProviderConfig config, {
    required ExternalProviderConsentScope scope,
  }) async {
    await _store.remove(_providerAcknowledgementKey(config, scope: scope));
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
  ExternalProviderSettingsController({
    required ExternalProviderRepository repository,
    required ExternalPrivacyConfirmationController confirmation,
    required ExternalChatGateway gateway,
    required Future<void> Function(ExternalProviderConfig config)
    testConnection,
    required void Function() invalidateProviderState,
  }) : _repository = repository,
       _confirmation = confirmation,
       _gateway = gateway,
       _testConnection = testConnection,
       _invalidateProviderState = invalidateProviderState;

  final ExternalProviderRepository _repository;
  final ExternalPrivacyConfirmationController _confirmation;
  final ExternalChatGateway _gateway;
  final Future<void> Function(ExternalProviderConfig config) _testConnection;
  final void Function() _invalidateProviderState;

  Future<void> save(ExternalProviderConfig config) async {
    final existing = await _repository.loadById(config.id);
    if (existing != null) {
      await _invalidateChangedConsent(existing: existing, updated: config);
    }
    final previouslyEnabled = await _repository.loadEnabled();
    if (config.enabled &&
        previouslyEnabled != null &&
        previouslyEnabled.id != config.id) {
      await _confirmation.revoke(previouslyEnabled);
      _gateway.invalidateConfiguration(previouslyEnabled.id);
    }
    await _repository.save(config);
    if (existing?.enabled == true && !config.enabled) {
      _gateway.invalidateConfiguration(config.id);
    }
    _invalidateProviderState();
  }

  Future<void> setEnabled(
    ExternalProviderConfig config, {
    required bool enabled,
  }) async {
    final persisted = await _repository.loadById(config.id) ?? config;
    await save(persisted.copyWith(enabled: enabled));
  }

  Future<void> revokeConsent(ExternalProviderConfig config) async {
    final persisted = await _repository.loadById(config.id) ?? config;
    await _confirmation.revoke(persisted);
    _gateway.invalidateConfiguration(persisted.id);
  }

  Future<void> _invalidateChangedConsent({
    required ExternalProviderConfig existing,
    required ExternalProviderConfig updated,
  }) async {
    final oldStandard = externalProviderConsentFingerprint(
      existing,
      scope: ExternalProviderConsentScope.standard,
    );
    final newStandard = externalProviderConsentFingerprint(
      updated,
      scope: ExternalProviderConsentScope.standard,
    );
    if (oldStandard != newStandard) {
      await _confirmation.revoke(existing);
      _gateway.invalidateConfiguration(existing.id);
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
      await _confirmation.revokeScope(
        existing,
        scope: ExternalProviderConsentScope.privateContext,
      );
      _gateway.invalidateFingerprint(oldPrivate);
    }
  }

  Future<void> testConnection(ExternalProviderConfig config) async {
    await _testConnection(config);
  }
}
