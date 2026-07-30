part of 'ai_chat_page_test.dart';

Future<ProviderContainer> _buildContainer({
  LocalLlmReadiness? llmReadiness,
  SemanticSearchReadiness? semanticReadiness,
  ChatSessionRepository? chatRepository,
  ExternalProviderStatus? externalStatus,
  ExternalProviderConsentStore? externalConsentStore,
  List<Override> extraOverrides = const <Override>[],
}) async {
  return ProviderContainer(
    overrides: [
      lockSessionControllerProvider.overrideWith(
        (ref) => LockSessionController()..markUnlocked(UnlockMethod.biometric),
      ),
      sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
      localLlmReadinessProvider.overrideWith(
        (ref) async =>
            llmReadiness ??
            const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: null,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
      ),
      semanticSearchReadinessProvider.overrideWith(
        (ref) async =>
            semanticReadiness ??
            const SemanticSearchReadiness(ready: true, reason: 'ready'),
      ),
      externalProviderStatusProvider.overrideWith(
        (ref) async =>
            externalStatus ??
            const ExternalProviderStatus(
              available: false,
              reason: '尚未启用外部模型提供方。',
              config: null,
            ),
      ),
      externalProviderConsentStoreProvider.overrideWithValue(
        externalConsentStore ?? _MemoryExternalProviderConsentStore(),
      ),
      chatSessionRepositoryProvider.overrideWithValue(
        chatRepository ?? const _FakeChatSessionRepository(),
      ),
      ...extraOverrides,
    ],
  );
}

Future<void> _pumpChatRouteAtSize(
  WidgetTester tester,
  ProviderContainer container, {
  required Size size,
}) async {
  final router = container.read(appRouterProvider);
  router.go('/ai/chat');

  await pumpRouteAtViewport(
    tester,
    viewport: size,
    route: UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await pumpUntilProviderSettled(tester, container, localLlmReadinessProvider);
  await pumpUntilProviderSettled(
    tester,
    container,
    externalProviderStatusProvider,
  );
  await pumpUntilProviderSettled(tester, container, chatSessionsProvider);
  await pumpUntilFound(tester, find.text('AI 问答'));
}

class _MemoryExternalProviderConsentStore
    implements ExternalProviderConsentStore {
  _MemoryExternalProviderConsentStore({
    Map<String, bool> initialValues = const <String, bool>{},
  }) : _values = Map<String, bool>.from(initialValues);

  final Map<String, bool> _values;

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

const _embeddingModel = ModelRegistryEntry(
  id: 'embed-1',
  type: 'embedding',
  provider: 'builtin',
  name: 'MiniLM Embedding',
  version: '1.0.0',
  sizeBytes: 10485760,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'mvp',
  localPath: '/data/models/minilm.onnx',
  checksum: 'embedding-checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

const _localLlmModel = ModelRegistryEntry(
  id: 'llm-local',
  type: 'llm',
  provider: 'builtin',
  name: 'Qwen Local',
  version: '1.0.0',
  sizeBytes: 1024,
  quantization: 'Q4_K_M',
  minRamMb: 2048,
  recommendedTier: 'mvp',
  localPath: '/data/models/qwen.gguf',
  checksum: 'llm-checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
);

class _FakeChatSessionRepository implements ChatSessionRepository {
  const _FakeChatSessionRepository({
    this.sessions = const <ChatSession>[],
    this.messagesBySession = const <String, List<ChatStoredMessage>>{},
  });

  final List<ChatSession> sessions;
  final Map<String, List<ChatStoredMessage>> messagesBySession;

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    return sessions.where((session) => session.id == sessionId).firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    return messagesBySession[sessionId] ?? const <ChatStoredMessage>[];
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    final sorted = List<ChatSession>.from(sessions)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return sorted;
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {}

  @override
  Future<void> saveSession(ChatSession session) async {}
}

class _ImmediateExternalProviderClient implements ExternalProviderClient {
  @override
  Future<String> generateChatCompletion({
    required ExternalProviderConfig config,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    return '来自外部模型的回答';
  }

  @override
  Future<void> testConnection(ExternalProviderConfig config) async {}
}

class _StaticContextRetriever implements AiChatContextRetriever {
  const _StaticContextRetriever({required this.items});

  final List<ChatContextItem> items;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required ModelRegistryEntry embeddingModel,
  }) async {
    return items;
  }
}

class _RecordingLlmEngine implements LlmEngine {
  _RecordingLlmEngine({required this.responseText});

  final String responseText;
  LlmInferenceRequest? lastRequest;

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    lastRequest = request;
    return LlmInferenceResponse(
      text: responseText,
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
