part of 'ai_chat_providers_test.dart';

const _llmModel = ModelRegistryEntry(
  id: 'llm-1',
  type: 'llm',
  provider: 'builtin',
  name: 'Phi Local',
  version: '1.0.0',
  sizeBytes: 104857600,
  quantization: 'Q4_K_M',
  minRamMb: 2048,
  recommendedTier: 'local',
  localPath: '/data/models/phi.gguf',
  checksum: 'abc',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _embeddingModel = ModelRegistryEntry(
  id: 'embed-1',
  type: 'embedding',
  provider: 'builtin',
  name: 'MiniLM Embedding',
  version: '1.0.2',
  sizeBytes: 10485760,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'mvp',
  localPath: '/data/models/minilm.onnx',
  checksum: 'def',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _externalProvider = ExternalProviderConfig(
  id: 'provider-1',
  providerType: ExternalProviderType.openAiCompatible,
  displayName: 'OpenAI 兼容服务',
  baseUrl: 'https://example.com/v1',
  apiKey: 'secret-key',
  modelName: 'gpt-4.1-mini',
  embeddingModelName: 'text-embedding-3-small',
  enabled: true,
  allowSensitiveFields: true,
);

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

class _FakeAiChatContextRetriever implements AiChatContextRetriever {
  _FakeAiChatContextRetriever({this.onRetrieve, required this.items});

  final void Function()? onRetrieve;
  final List<ChatContextItem> items;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required ModelRegistryEntry embeddingModel,
  }) async {
    onRetrieve?.call();
    return items;
  }
}

class _FakeChatContextProjector implements ChatContextProjector {
  const _FakeChatContextProjector(this.projectedItems);

  final List<ProjectedChatContextItem> projectedItems;

  @override
  Future<List<ProjectedChatContextItem>> projectManual({
    required List<ChatContextItem> items,
    required SearchConfiguration configuration,
    required ChatContextProjectionTarget target,
  }) async {
    return projectedItems;
  }
}

class _FakeLlmEngine implements LlmEngine {
  _FakeLlmEngine({this.onGenerate});

  final void Function(LlmInferenceRequest request)? onGenerate;
  LlmInferenceRequest? lastRequest;
  final List<LlmInferenceRequest> requests = <LlmInferenceRequest>[];

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    lastRequest = request;
    requests.add(request);
    onGenerate?.call(request);
    return LlmInferenceResponse(
      text: request.usedPrivateContext ? '结合私密上下文后的回答' : '普通回答',
      finishReason: 'stop',
      usedPrivateContext: request.usedPrivateContext,
    );
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) {
    throw UnimplementedError();
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _FailThenSucceedLlmEngine implements LlmEngine {
  final List<LlmInferenceRequest> requests = <LlmInferenceRequest>[];

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    requests.add(request);
    if (requests.length == 1) {
      throw StateError('RAW_FAILURE_SENTINEL');
    }
    return LlmInferenceResponse(
      text: 'recovered',
      finishReason: 'stop',
      usedPrivateContext: request.usedPrivateContext,
    );
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) {
    throw UnimplementedError();
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _ThrowingLlmEngine implements LlmEngine {
  _ThrowingLlmEngine({this.message = 'generation failed'});

  final String message;

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    throw StateError(message);
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) {
    throw UnimplementedError();
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _FakeExternalProviderClient implements ExternalProviderClient {
  String? lastPrompt;
  bool? lastUsedPrivateContext;

  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    lastPrompt = prompt;
    lastUsedPrivateContext = usedPrivateContext;
    return '来自外部模型的回答';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
}

class _FakeChatSessionRepository implements ChatSessionRepository {
  final List<ChatSession> savedSessions = <ChatSession>[];
  final List<ChatStoredMessage> savedMessages = <ChatStoredMessage>[];

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    return savedSessions
        .where((session) => session.id == sessionId)
        .firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    return savedMessages
        .where((message) => message.sessionId == sessionId)
        .toList(growable: false);
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    final sorted = List<ChatSession>.from(savedSessions)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {
    savedMessages.removeWhere((item) => item.id == message.id);
    savedMessages.add(message);
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    savedSessions.removeWhere((item) => item.id == session.id);
    savedSessions.add(session);
  }
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
