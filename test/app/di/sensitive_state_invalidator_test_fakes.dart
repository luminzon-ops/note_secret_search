part of 'sensitive_state_invalidator_provider_test.dart';

const _manualContext = ChatContextItem(
  id: 'secret-sensitive',
  type: ChatContextItemType.secret,
  title: 'Sensitive secret',
  preview: 'private preview',
  summary: 'private summary',
);

const _plaintextCryptoService = _PlaintextTestCryptoService();

class _PlaintextTestCryptoService implements CryptoService {
  const _PlaintextTestCryptoService();

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    return plaintext == null
        ? null
        : Uint8List.fromList(utf8.encode(plaintext));
  }

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return ciphertext == null ? '' : utf8.decode(ciphertext);
  }
}

Uint8List _plaintextCiphertext(String value) {
  return _plaintextCryptoService.encryptNullable(
    value,
    context: FieldCryptoContext(
      table: 'test_fixture',
      rowId: 'sensitive-state',
      column: 'plaintext',
    ),
  )!;
}

class _VaultRepository implements VaultRepository {
  var reads = 0;

  @override
  Future<Vault?> getDefaultVault() async {
    reads++;
    return Vault(
      id: 'vault-sensitive',
      name: 'Sensitive vault',
      description: 'private description',
      isDefault: true,
      encryptionVersion: 1,
      createdAt: DateTime(2026, 7, 14),
      updatedAt: DateTime(2026, 7, 14),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SecretRepository implements SecretRepository {
  var reads = 0;
  final item = SecretItem(
    id: 'secret-sensitive',
    vaultId: 'vault-sensitive',
    title: 'Sensitive secret',
    usernameCiphertext: _plaintextCiphertext('private-user'),
    passwordCiphertext: _plaintextCiphertext('private-password'),
    websiteUrlCiphertext: null,
    noteCiphertext: _plaintextCiphertext('private note'),
    tags: const ['private'],
    categoryId: null,
    favorite: true,
    createdAt: DateTime(2026, 7, 14),
    updatedAt: DateTime(2026, 7, 14),
  );

  @override
  Future<SecretItem?> getById(String id) async {
    reads++;
    return id == item.id ? item : null;
  }

  @override
  Future<List<SecretItem>> listByVault(String vaultId) async {
    reads++;
    return [item];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoteRepository implements NoteRepository {
  var reads = 0;
  final item = NoteItem(
    id: 'note-sensitive',
    vaultId: 'vault-sensitive',
    title: 'Sensitive note',
    contentCiphertext: _plaintextCiphertext('private note body'),
    summaryCacheCiphertext: _plaintextCiphertext('private summary'),
    tags: const ['private'],
    categoryId: null,
    favorite: true,
    createdAt: DateTime(2026, 7, 14),
    updatedAt: DateTime(2026, 7, 14),
  );

  @override
  Future<NoteItem?> getById(String id) async {
    reads++;
    return id == item.id ? item : null;
  }

  @override
  Future<List<NoteItem>> listByVault(String vaultId) async {
    reads++;
    return [item];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChatRepository implements ChatSessionRepository {
  var reads = 0;

  final sessions = [
    _chatSession('chat-free', ChatMode.freeChat),
    _chatSession('chat-private', ChatMode.privateQa),
  ];

  @override
  Future<ChatSession?> getSession(String sessionId) async {
    reads++;
    return sessions.where((session) => session.id == sessionId).firstOrNull;
  }

  @override
  Future<List<ChatStoredMessage>> listMessages(String sessionId) async {
    reads++;
    return [
      ChatStoredMessage(
        id: 'message-$sessionId',
        sessionId: sessionId,
        role: ChatStoredMessageRole.user,
        content: 'sensitive chat plaintext',
        status: ChatStoredMessageStatus.completed,
        createdAt: DateTime(2026, 7, 14),
      ),
    ];
  }

  @override
  Future<List<ChatSession>> listSessions() async {
    reads++;
    return sessions;
  }

  @override
  Future<void> saveMessage(ChatStoredMessage message) async {}

  @override
  Future<void> saveSession(ChatSession session) async {}
}

ChatSession _chatSession(String id, ChatMode mode) {
  return ChatSession(
    id: id,
    mode: mode,
    title: 'Sensitive chat session',
    allowPrivateContext: true,
    lastModelId: _llmModel.id,
    archived: false,
    createdAt: DateTime(2026, 7, 14),
    updatedAt: DateTime(2026, 7, 14),
  );
}

class _ExternalRepository implements ExternalProviderRepository {
  var reads = 0;

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    reads++;
    return _externalConfig;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RegistryRepository implements ModelRegistryRepository {
  var reads = 0;

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async {
    reads++;
    return const [_embeddingModel, _llmModel];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DownloadRepository implements ModelDownloadRepository {
  var reads = 0;

  @override
  Future<List<ModelDownloadTask>> listTasks() async {
    reads++;
    return [
      ModelDownloadTask(
        id: 'download-sensitive',
        modelId: _llmModel.id,
        sourceId: 'private-source',
        status: ModelDownloadStatus.failed,
        totalBytes: 2048,
        downloadedBytes: 1024,
        averageSpeed: null,
        errorMessage: '/private/models/llm.gguf failed',
        resumable: true,
        createdAt: DateTime(2026, 7, 14),
        updatedAt: DateTime(2026, 7, 14),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AlwaysPresentModelDownloadService extends ModelDownloadService {
  _AlwaysPresentModelDownloadService()
    : super(dio: Dio(), logger: const AppLogger());

  @override
  Future<bool> fileExists(String? path) async => true;
}

class _ReadyEmbeddingEngine implements EmbeddingEngine {
  var stateReads = 0;

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    return const EmbeddingVector(values: [1], tokenCount: 1);
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    stateReads++;
    return EmbeddingEngineState(
      ready: true,
      reason: 'ready at ${model.localPath}',
      status: EmbeddingRuntimeStatus.ready,
      vectorDimension: 1,
      modelPath: model.localPath,
    );
  }
}

class _ReadyLlmEngine implements LlmEngine {
  var stateReads = 0;

  @override
  Future<LlmInferenceResponse> generate(LlmInferenceRequest request) async {
    return const LlmInferenceResponse(
      text: 'sensitive response',
      finishReason: 'stop',
      usedPrivateContext: true,
    );
  }

  @override
  Future<LlmRuntimeState> getState(ModelRegistryEntry model) async {
    stateReads++;
    return LlmRuntimeState(
      ready: true,
      reason: 'ready at ${model.localPath}',
      status: LlmRuntimeStatus.ready,
      modelPath: model.localPath,
    );
  }

  @override
  Future<void> releaseModel(String modelId) async {}
}

class _SearchRepository implements SearchRepository, EmbeddingIndexRepository {
  var chunkReads = 0;

  @override
  Future<List<LegacyEmbeddingChunk>> getChunksBySource(
    String sourceId,
    SearchSourceType sourceType,
    String modelId,
  ) async {
    chunkReads++;
    return const [];
  }

  @override
  Future<SearchScopeConfig> loadScopeConfig() async {
    return const SearchScopeConfig.defaults();
  }

  @override
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  ) async => null;

  @override
  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey) async {}

  @override
  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SensitiveSemanticSearchService extends SemanticSearchService {
  _SensitiveSemanticSearchService({
    required super.repository,
    required super.embeddingEngine,
  }) : super(cryptoService: _plaintextCryptoService);

  var searchReads = 0;

  @override
  Future<List<SemanticSearchResult>> search({
    required String query,
    required SearchScopeConfig scope,
    required ModelRegistryEntry activeEmbeddingModel,
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
  }) async {
    searchReads++;
    return [
      SemanticSearchResult(
        item: SearchResultItem(
          id: 'secret-sensitive',
          type: SearchResultType.secret,
          title: 'Sensitive secret',
          preview: 'private semantic preview',
          tags: const ['private'],
          favorite: true,
          updatedAt: DateTime(2026, 7, 14),
        ),
        score: 0.99,
        hitSummary: 'private semantic summary',
        hitField: SemanticHitField.secretNote,
      ),
    ];
  }
}
