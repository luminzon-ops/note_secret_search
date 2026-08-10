part of 'ai_provider_providers_test.dart';

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

class _SharedPreferencesConsentStore implements ExternalProviderConsentStore {
  const _SharedPreferencesConsentStore();

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<bool> read(String key) async {
    return (await _preferences).getBool(key) ?? false;
  }

  @override
  Future<void> remove(String key) async {
    await (await _preferences).remove(key);
  }

  @override
  Future<void> write(String key, bool value) async {
    await (await _preferences).setBool(key, value);
  }
}
