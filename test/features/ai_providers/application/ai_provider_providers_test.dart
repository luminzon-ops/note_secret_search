import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
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
    final repository = _MemoryExternalProviderRepository(configs: const [_provider]);
    final container = ProviderContainer(
      overrides: [
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );

    addTearDown(container.dispose);

    final config = await container.read(enabledExternalProviderProvider.future);
    expect(config?.id, 'provider-1');
    expect(config?.baseUrl, 'https://example.com/v1');
  });

  test('externalProviderStatusProvider reports provider ready when config exists', () async {
    final repository = _MemoryExternalProviderRepository(configs: const [_provider]);
    final container = ProviderContainer(
      overrides: [
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );

    addTearDown(container.dispose);

    final status = await container.read(externalProviderStatusProvider.future);
    expect(status.available, isTrue);
    expect(status.reason, contains('OpenAI 兼容服务'));
    expect(status.config?.modelName, 'gpt-4.1-mini');
  });

  test('externalProviderStatusProvider reports unavailable when no config exists', () async {
    final repository = _MemoryExternalProviderRepository();
    final container = ProviderContainer(
      overrides: [
        externalProviderRepositoryProvider.overrideWithValue(repository),
      ],
    );

    addTearDown(container.dispose);

    final status = await container.read(externalProviderStatusProvider.future);
    expect(status.available, isFalse);
    expect(status.config, isNull);
  });

  test('externalPrivacyConfirmationController persists provider confirmation per provider id', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => SharedPreferences.getInstance()),
      ],
    );

    addTearDown(container.dispose);

    final controller = container.read(externalPrivacyConfirmationControllerProvider);

    expect(await controller.hasAcknowledged('provider-1'), isFalse);
    await controller.markAcknowledged('provider-1');
    expect(await controller.hasAcknowledged('provider-1'), isTrue);
    expect(await controller.hasAcknowledged('provider-2'), isFalse);
  });

  test('externalProviderSettingsController saves config and can test connection', () async {
    final repository = _MemoryExternalProviderRepository();
    final client = _RecordingExternalProviderClient();
    final container = ProviderContainer(
      overrides: [
        externalProviderRepositoryProvider.overrideWithValue(repository),
        externalProviderClientProvider.overrideWithValue(client),
      ],
    );

    addTearDown(container.dispose);

    final controller = container.read(externalProviderSettingsControllerProvider);

    await controller.save(_provider);
    await controller.testConnection(_provider);

    expect(repository.saved.single.id, 'provider-1');
    expect(client.lastTested?.baseUrl, 'https://example.com/v1');
  });
}

class _MemoryExternalProviderRepository implements ExternalProviderRepository {
  _MemoryExternalProviderRepository({List<ExternalProviderConfig> configs = const <ExternalProviderConfig>[]})
      : _configs = List<ExternalProviderConfig>.from(configs);

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
