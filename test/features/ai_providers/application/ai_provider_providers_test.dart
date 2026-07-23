import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _provider = ExternalProviderConfig(
  id: 'provider-1',
  providerType: ExternalProviderType.openAiCompatible,
  displayName: 'OpenAI 兼容服务',
  baseUrl: 'https://example.com/v1',
  apiKey: 'secret-key',
  modelName: 'gpt-4.1-mini',
  embeddingModelName: 'text-embedding-3-small',
  enabled: true,
  allowSensitiveFields: false,
);

void main() {
  test('enabledExternalProviderProvider returns the enabled config', () async {
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );

    addTearDown(container.dispose);

    final config = await container.read(enabledExternalProviderProvider.future);
    expect(config?.id, 'provider-1');
    expect(config?.baseUrl, 'https://example.com/v1');
  });

  test(
    'externalProviderStatusProvider reports provider ready when config exists',
    () async {
      final repository = _MemoryExternalProviderRepository(
        configs: const [_provider],
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderRepositoryProvider.overrideWithValue(repository),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults().copyWith(
              allowExternalProviderAccess: true,
            ),
          ),
        ],
      );

      addTearDown(container.dispose);

      final status = await container.read(
        externalProviderStatusProvider.future,
      );
      expect(status.available, isTrue);
      expect(status.reason, contains('OpenAI 兼容服务'));
      expect(status.config?.modelName, 'gpt-4.1-mini');
    },
  );

  test(
    'externalProviderStatusProvider reports unavailable when no config exists',
    () async {
      final repository = _MemoryExternalProviderRepository();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderRepositoryProvider.overrideWithValue(repository),
        ],
      );

      addTearDown(container.dispose);

      final status = await container.read(
        externalProviderStatusProvider.future,
      );
      expect(status.available, isFalse);
      expect(status.config, isNull);
    },
  );

  test(
    'externalProviderStatusProvider reports unavailable before global opt-in',
    () async {
      final repository = _MemoryExternalProviderRepository(
        configs: const [_provider],
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          externalProviderRepositoryProvider.overrideWithValue(repository),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
        ],
      );

      addTearDown(container.dispose);

      final status = await container.read(
        externalProviderStatusProvider.future,
      );
      expect(status.available, isFalse);
      expect(status.reason, contains('尚未允许外部 AI 访问'));
      expect(status.config?.id, _provider.id);
    },
  );

  test(
    'external provider consent fingerprint canonicalizes endpoint and ignores display metadata',
    () {
      final equivalent = _provider.copyWith(
        displayName: 'Renamed',
        baseUrl: ' HTTPS://EXAMPLE.COM/v1/// ',
        updatedAt: DateTime(2026, 7, 22),
      );

      expect(
        normalizeExternalProviderEndpoint(equivalent.baseUrl),
        'https://example.com/v1',
      );
      expect(
        externalProviderConsentFingerprint(equivalent),
        externalProviderConsentFingerprint(_provider),
      );
    },
  );

  test(
    'external provider consent fingerprint changes with bound configuration',
    () {
      final baseline = externalProviderConsentFingerprint(_provider);

      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(baseUrl: 'https://other.example.com/v1'),
        ),
        isNot(baseline),
      );
      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(modelName: 'gpt-4.1'),
        ),
        isNot(baseline),
      );
      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(providerType: ExternalProviderType.ollama),
        ),
        isNot(baseline),
      );
      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(id: 'provider-2'),
        ),
        isNot(baseline),
      );
      expect(
        externalProviderConsentFingerprint(
          _provider.copyWith(apiKey: 'rotated-key'),
        ),
        isNot(baseline),
      );
    },
  );

  test('private policy changes invalidate only private consent', () {
    final changed = _provider.copyWith(allowSensitiveFields: true);

    expect(
      externalProviderConsentFingerprint(
        changed,
        scope: ExternalProviderConsentScope.standard,
      ),
      externalProviderConsentFingerprint(
        _provider,
        scope: ExternalProviderConsentScope.standard,
      ),
    );
    expect(
      externalProviderConsentFingerprint(
        changed,
        scope: ExternalProviderConsentScope.privateContext,
      ),
      isNot(
        externalProviderConsentFingerprint(
          _provider,
          scope: ExternalProviderConsentScope.privateContext,
        ),
      ),
    );
  });

  test(
    'external privacy confirmation is bound to the current config fingerprint',
    () async {
      SharedPreferences.setMockInitialValues({
        'ai.external_privacy_ack.provider-1': true,
      });
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          sharedPreferencesProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(
        externalPrivacyConfirmationControllerProvider,
      );

      expect(
        await controller.hasAcknowledged(
          _provider,
          includesPrivateContext: false,
        ),
        isFalse,
      );
      await controller.markAcknowledged(
        _provider,
        includesPrivateContext: false,
      );
      expect(
        await controller.hasAcknowledged(
          _provider,
          includesPrivateContext: false,
        ),
        isTrue,
      );
      expect(
        await controller.hasAcknowledged(
          _provider,
          includesPrivateContext: true,
        ),
        isFalse,
      );
      expect(
        await controller.hasAcknowledged(
          _provider.copyWith(modelName: 'gpt-4.1'),
          includesPrivateContext: false,
        ),
        isFalse,
      );
      await controller.revoke(_provider);
      expect(
        await controller.hasAcknowledged(
          _provider,
          includesPrivateContext: false,
        ),
        isFalse,
      );
    },
  );

  test(
    'externalProviderSettingsController revokes old consent when saving config',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = _MemoryExternalProviderRepository(
        configs: const [_provider],
      );
      final client = _RecordingExternalProviderClient();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          sharedPreferencesProvider.overrideWith(
            (ref) async => SharedPreferences.getInstance(),
          ),
          externalProviderRepositoryProvider.overrideWithValue(repository),
          externalProviderClientRouterProvider.overrideWithValue(client),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(
        externalProviderSettingsControllerProvider,
      );
      final confirmation = container.read(
        externalPrivacyConfirmationControllerProvider,
      );
      final updated = _provider.copyWith(modelName: 'gpt-4.1');

      await confirmation.markAcknowledged(
        _provider,
        includesPrivateContext: true,
      );
      expect(
        await confirmation.hasAcknowledged(
          _provider,
          includesPrivateContext: true,
        ),
        isTrue,
      );

      await controller.save(updated);
      await controller.testConnection(updated);

      expect(repository.saved.single.id, 'provider-1');
      expect(
        await confirmation.hasAcknowledged(
          _provider,
          includesPrivateContext: true,
        ),
        isFalse,
      );
      expect(
        await confirmation.hasAcknowledged(
          updated,
          includesPrivateContext: true,
        ),
        isFalse,
      );
      expect(client.lastTested?.baseUrl, 'https://example.com/v1');
    },
  );

  test('display metadata changes preserve both consent scopes', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        sharedPreferencesProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final confirmation = container.read(
      externalPrivacyConfirmationControllerProvider,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: false,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: true,
    );

    final renamed = _provider.copyWith(displayName: 'Renamed provider');
    await container
        .read(externalProviderSettingsControllerProvider)
        .save(renamed);

    expect(
      await confirmation.hasAcknowledged(
        renamed,
        includesPrivateContext: false,
      ),
      isTrue,
    );
    expect(
      await confirmation.hasAcknowledged(renamed, includesPrivateContext: true),
      isTrue,
    );
  });

  test('private policy changes revoke only private consent', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        sharedPreferencesProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final confirmation = container.read(
      externalPrivacyConfirmationControllerProvider,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: false,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: true,
    );

    final changed = _provider.copyWith(allowSensitiveFields: true);
    await container
        .read(externalProviderSettingsControllerProvider)
        .save(changed);

    expect(
      await confirmation.hasAcknowledged(
        changed,
        includesPrivateContext: false,
      ),
      isTrue,
    );
    expect(
      await confirmation.hasAcknowledged(changed, includesPrivateContext: true),
      isFalse,
    );
  });

  test('explicit revoke clears both consent scopes', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        sharedPreferencesProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final confirmation = container.read(
      externalPrivacyConfirmationControllerProvider,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: false,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: true,
    );

    await container
        .read(externalProviderSettingsControllerProvider)
        .revokeConsent(_provider);

    expect(
      await confirmation.hasAcknowledged(
        _provider,
        includesPrivateContext: false,
      ),
      isFalse,
    );
    expect(
      await confirmation.hasAcknowledged(
        _provider,
        includesPrivateContext: true,
      ),
      isFalse,
    );
  });

  test('explicit revoke reloads the persisted fingerprint by config id', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MemoryExternalProviderRepository(
      configs: const [_provider],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        sharedPreferencesProvider.overrideWith(
          (ref) async => SharedPreferences.getInstance(),
        ),
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final confirmation = container.read(
      externalPrivacyConfirmationControllerProvider,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: false,
    );
    await confirmation.markAcknowledged(
      _provider,
      includesPrivateContext: true,
    );

    await container
        .read(externalProviderSettingsControllerProvider)
        .revokeConsent(
          _provider.copyWith(
            providerType: ExternalProviderType.ollama,
            baseUrl: 'http://localhost:11434',
            apiKey: '',
            modelName: 'unsaved-model',
          ),
        );

    expect(
      await confirmation.hasAcknowledged(
        _provider,
        includesPrivateContext: false,
      ),
      isFalse,
    );
    expect(
      await confirmation.hasAcknowledged(
        _provider,
        includesPrivateContext: true,
      ),
      isFalse,
    );
  });
}

class _MemoryExternalProviderRepository implements ExternalProviderRepository {
  _MemoryExternalProviderRepository({
    List<ExternalProviderConfig> configs = const <ExternalProviderConfig>[],
  }) : _configs = List<ExternalProviderConfig>.from(configs);

  final List<ExternalProviderConfig> _configs;
  final List<ExternalProviderConfig> saved = <ExternalProviderConfig>[];

  @override
  Future<ExternalProviderConfig?> loadById(String id) async {
    for (final config in _configs.reversed) {
      if (config.id == id) {
        return config;
      }
    }
    return null;
  }

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    for (final config in _configs.reversed) {
      if (config.enabled) {
        return config;
      }
    }
    return null;
  }

  @override
  Future<List<ExternalProviderConfig>> loadAll() async {
    return List<ExternalProviderConfig>.from(_configs);
  }

  @override
  Future<void> save(ExternalProviderConfig config) async {
    _configs.removeWhere((item) => item.id == config.id);
    if (config.enabled) {
      for (var index = 0; index < _configs.length; index++) {
        _configs[index] = _configs[index].copyWith(enabled: false);
      }
    }
    _configs.add(config);
    saved.add(config);
  }
}

class _RecordingExternalProviderClient implements ExternalProviderClient {
  ExternalProviderConfig? lastTested;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {
    lastTested = config;
  }
}
