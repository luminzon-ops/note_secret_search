part of 'ai_chat_orchestration_test.dart';

class _MemoryExternalProviderConsentStore
    implements ExternalProviderConsentStore {
  final Map<String, bool> _values = <String, bool>{};

  @override
  Future<bool> read(String key) async => _values[key] ?? false;

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> write(String key, bool value) async {
    _values[key] = value;
  }
}

class _FakeChatSessionRepository implements ChatSessionRepository {
  const _FakeChatSessionRepository();

  @override
  Future<ChatSession?> getSession(String sessionId) async => null;

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async =>
      const <ChatStoredMessage>[];

  @override
  Future<List<ChatSession>> listSessions() async => const <ChatSession>[];

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {}

  @override
  Future<void> saveSession(ChatSession session) async {}
}

class _RecordingExternalProviderClient implements ExternalProviderClient {
  int generateCallCount = 0;
  bool? lastUsedPrivateContext;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    generateCallCount++;
    lastUsedPrivateContext = usedPrivateContext;
    return '外部回复';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
}

class _MemoryExternalProviderRepository implements ExternalProviderRepository {
  _MemoryExternalProviderRepository({
    List<ExternalProviderConfig> configs = const <ExternalProviderConfig>[],
  }) : _configs = List<ExternalProviderConfig>.from(configs);

  final List<ExternalProviderConfig> _configs;

  @override
  Future<List<ExternalProviderConfig>> loadAll() async {
    return List<ExternalProviderConfig>.from(_configs);
  }

  @override
  Future<ExternalProviderConfig?> loadById(String id) async {
    return _configs.where((config) => config.id == id).firstOrNull;
  }

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    return _configs.where((config) => config.enabled).firstOrNull;
  }

  @override
  Future<void> save(ExternalProviderConfig config) async {
    _configs.removeWhere((item) => item.id == config.id);
    _configs.add(config);
  }
}

class _StaticContextRetriever implements AiChatContextRetriever {
  const _StaticContextRetriever({required this.items});

  final List<ChatContextItem> items;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required dynamic embeddingModel,
  }) async {
    return items;
  }
}
