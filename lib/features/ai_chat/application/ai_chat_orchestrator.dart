part of 'ai_chat_providers.dart';

class AiChatOrchestrator {
  AiChatOrchestrator({required Ref ref}) : _ref = ref;

  final Ref _ref;
  final Map<String, _ActiveChatOperation> _activeOperations =
      <String, _ActiveChatOperation>{};

  Future<AiChatResponse> send(
    AiChatRequest request, {
    List<ChatHistoryTurn> history = const <ChatHistoryTurn>[],
  }) async {
    final userInput = request.userInput.trim();
    if (userInput.isEmpty) {
      throw StateError('请输入问题或消息。');
    }
    final requestId = request.requestId?.trim().isNotEmpty == true
        ? request.requestId!.trim()
        : const Uuid().v4();
    if (_activeOperations.containsKey(requestId)) {
      throw StateError('该聊天请求正在处理中。');
    }
    final operation = _ActiveChatOperation();
    _activeOperations[requestId] = operation;

    try {
      final backend = await _resolveBackend(
        request.backendPreference,
        includesPrivateContext:
            request.mode == ChatMode.privateQa || request.allowPrivateContext,
      );
      operation.backend = backend;
      _throwIfCancelled(operation);
      final response = await switch (request.mode) {
        ChatMode.privateQa => _runPrivateQa(
          userInput: userInput,
          requestId: requestId,
          backend: backend,
          history: history,
          operation: operation,
        ),
        ChatMode.freeChat => _runFreeChat(
          userInput: userInput,
          requestId: requestId,
          request: request,
          backend: backend,
          history: history,
          operation: operation,
        ),
      };
      return response;
    } on ExternalChatGatewayException catch (error) {
      if (error.code == ExternalChatGatewayErrorCode.cancelled) {
        throw const AiChatCancelledException();
      }
      rethrow;
    } on LlmGenerationCancelledException {
      throw const AiChatCancelledException();
    } finally {
      if (identical(_activeOperations[requestId], operation)) {
        _activeOperations.remove(requestId);
      }
    }
  }

  Future<void> cancel(String requestId) async {
    final operation = _activeOperations[requestId];
    if (operation == null) {
      return;
    }
    operation.cancelled = true;
    final backend = operation.backend;
    if (backend == null) {
      return;
    }
    await _cancelBackend(backend, requestId);
  }

  Future<void> _cancelBackend(
    _ResolvedChatBackend backend,
    String requestId,
  ) async {
    if (backend.type == _ChatBackendType.external) {
      backend.externalGateway?.cancel(requestId);
      return;
    }
    final engine = backend.llmEngine;
    if (engine is CancellableLlmEngine) {
      await (engine as CancellableLlmEngine).cancelGeneration(requestId);
    }
  }

  Future<_ResolvedChatBackend> _resolveBackend(
    ChatBackendPreference preference, {
    required bool includesPrivateContext,
  }) async {
    return switch (preference) {
      ChatBackendPreference.local => _resolveLocalBackend(),
      ChatBackendPreference.external => _resolveExternalBackend(
        includesPrivateContext: includesPrivateContext,
      ),
    };
  }

  Future<_ResolvedChatBackend> _resolveLocalBackend() async {
    final llmReadiness = await _ref.read(localLlmReadinessProvider.future);
    if (!llmReadiness.ready || llmReadiness.activeModel == null) {
      throw StateError(llmReadiness.reason);
    }
    return _ResolvedChatBackend.local(
      llmEngine: _ref.read(llmEngineProvider),
      llmModel: llmReadiness.activeModel!,
      reason: llmReadiness.reason,
    );
  }

  Future<_ResolvedChatBackend> _resolveExternalBackend({
    required bool includesPrivateContext,
  }) async {
    final gateway = _ref.read(externalChatGatewayProvider);
    final authorization = await gateway.authorize(
      includesPrivateContext: includesPrivateContext,
    );
    return _ResolvedChatBackend.external(
      externalGateway: gateway,
      externalAuthorization: authorization,
      reason: '外部模型已授权：${authorization.providerType.name}',
    );
  }

  Future<AiChatResponse> _runPrivateQa({
    required String userInput,
    required String requestId,
    required _ResolvedChatBackend backend,
    required List<ChatHistoryTurn> history,
    required _ActiveChatOperation operation,
  }) async {
    final semanticReadiness = await _ref.read(
      semanticSearchReadinessProvider.future,
    );
    _throwIfCancelled(operation);
    if (!semanticReadiness.ready ||
        semanticReadiness.activeEmbeddingModel == null) {
      throw StateError(semanticReadiness.reason);
    }

    final contextItems = await _ref
        .read(aiChatContextRetrieverProvider)
        .retrieve(
          query: userInput,
          embeddingModel: semanticReadiness.activeEmbeddingModel!,
        );
    _throwIfCancelled(operation);
    final usedPrivateContext = contextItems.isNotEmpty;
    final prompt = _composePrompt(
      mode: ChatMode.privateQa,
      userInput: userInput,
      backend: backend,
      autoItems: contextItems,
      history: history,
      includesPrivateContext: true,
    );
    final generated = await _generateText(
      backend: backend,
      requestId: requestId,
      prompt: prompt.prompt,
      usedPrivateContext: usedPrivateContext,
    );

    return AiChatResponse(
      text: generated.text,
      usage: generated.usage,
      contextSummary: contextItems
          .map((item) => item.summary)
          .toList(growable: false),
      usedPrivateContext: usedPrivateContext,
      sourceType: usedPrivateContext
          ? ChatContextSource.autoRetrieved
          : ChatContextSource.none,
      contextItems: contextItems,
    );
  }

  Future<AiChatResponse> _runFreeChat({
    required String userInput,
    required String requestId,
    required AiChatRequest request,
    required _ResolvedChatBackend backend,
    required List<ChatHistoryTurn> history,
    required _ActiveChatOperation operation,
  }) async {
    _throwIfCancelled(operation);
    final manualItems = request.allowPrivateContext
        ? normalizeChatContextItems(request.manualItems)
        : const <ChatContextItem>[];
    var projectedManualItems = const <ProjectedChatContextItem>[];
    if (manualItems.isNotEmpty) {
      final configuration = await _ref.read(searchConfigurationProvider.future);
      _throwIfCancelled(operation);
      projectedManualItems = await _ref
          .read(chatContextProjectorProvider)
          .projectManual(
            items: manualItems,
            configuration: configuration,
            target: backend.type == _ChatBackendType.local
                ? ChatContextProjectionTarget.local
                : ChatContextProjectionTarget.external,
          );
      _throwIfCancelled(operation);
    }
    var autoItems = const <ChatContextItem>[];

    if (request.allowPrivateContext) {
      final semanticReadiness = await _ref.read(
        semanticSearchReadinessProvider.future,
      );
      _throwIfCancelled(operation);
      if (semanticReadiness.ready &&
          semanticReadiness.activeEmbeddingModel != null) {
        autoItems = await _ref
            .read(aiChatContextRetrieverProvider)
            .retrieve(
              query: userInput,
              embeddingModel: semanticReadiness.activeEmbeddingModel!,
            );
        _throwIfCancelled(operation);
      }
    }

    final contextItems = normalizeChatContextItems([
      ...autoItems,
      ...manualItems,
    ]);
    final usedPrivateContext = contextItems.isNotEmpty;
    _throwIfCancelled(operation);
    final prompt = _composePrompt(
      mode: ChatMode.freeChat,
      userInput: userInput,
      backend: backend,
      manualItems: projectedManualItems,
      autoItems: autoItems,
      history: history,
      includesPrivateContext: request.allowPrivateContext,
    );
    final generated = await _generateText(
      backend: backend,
      requestId: requestId,
      prompt: prompt.prompt,
      usedPrivateContext: usedPrivateContext,
    );

    return AiChatResponse(
      text: generated.text,
      usage: generated.usage,
      contextSummary: contextItems
          .map((item) => item.summary)
          .toList(growable: false),
      usedPrivateContext: usedPrivateContext,
      sourceType: _resolveSourceType(
        autoItems: autoItems,
        manualItems: manualItems,
      ),
      contextItems: contextItems,
    );
  }

  ChatPromptComposition _composePrompt({
    required ChatMode mode,
    required String userInput,
    required _ResolvedChatBackend backend,
    required List<ChatHistoryTurn> history,
    required bool includesPrivateContext,
    List<ProjectedChatContextItem> manualItems =
        const <ProjectedChatContextItem>[],
    List<ChatContextItem> autoItems = const <ChatContextItem>[],
  }) {
    return _ref
        .read(chatPromptComposerProvider)
        .compose(
          mode: mode,
          question: userInput,
          target: backend.type == _ChatBackendType.local
              ? ChatPromptTarget.local
              : ChatPromptTarget.external,
          manualItems: manualItems,
          history: history,
          autoItems: autoItems,
          externalProviderFingerprint:
              backend.externalAuthorization?.fingerprint,
          includesPrivateContext: includesPrivateContext,
        );
  }

  Future<_GeneratedChatResponse> _generateText({
    required _ResolvedChatBackend backend,
    required String requestId,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    return switch (backend.type) {
      _ChatBackendType.local => _generateLocal(
        backend: backend,
        requestId: requestId,
        prompt: prompt,
        usedPrivateContext: usedPrivateContext,
      ),
      _ChatBackendType.external => _generateExternal(
        backend: backend,
        requestId: requestId,
        prompt: prompt,
        usedPrivateContext: usedPrivateContext,
      ),
    };
  }

  Future<_GeneratedChatResponse> _generateLocal({
    required _ResolvedChatBackend backend,
    required String requestId,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    final response = await backend.llmEngine!.generate(
      LlmInferenceRequest(
        model: backend.llmModel!,
        requestId: requestId,
        prompt: prompt,
        usedPrivateContext: usedPrivateContext,
      ),
    );
    return _GeneratedChatResponse(
      text: response.text,
      usage:
          response.usage ??
          ChatBackendUsage(
            actualBackend: 'llama.cpp',
            actualModel: backend.llmModel!.id,
          ),
    );
  }

  Future<_GeneratedChatResponse> _generateExternal({
    required _ResolvedChatBackend backend,
    required String requestId,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    final result = await backend.externalGateway!.send(
      requestId: requestId,
      prompt: prompt,
      includesPrivateContext:
          backend.externalAuthorization!.includesPrivateContext,
      usedPrivateContext: usedPrivateContext,
      expectedFingerprint: backend.externalAuthorization!.fingerprint,
    );
    return _GeneratedChatResponse(text: result.text, usage: result.usage);
  }

  ChatContextSource _resolveSourceType({
    required List<ChatContextItem> autoItems,
    required List<ChatContextItem> manualItems,
  }) {
    if (autoItems.isNotEmpty && manualItems.isNotEmpty) {
      return ChatContextSource.mixed;
    }
    if (autoItems.isNotEmpty) {
      return ChatContextSource.autoRetrieved;
    }
    if (manualItems.isNotEmpty) {
      return ChatContextSource.manuallySelected;
    }
    return ChatContextSource.none;
  }

  void _throwIfCancelled(_ActiveChatOperation operation) {
    if (operation.cancelled) {
      throw const AiChatCancelledException();
    }
  }
}

class AiChatCancelledException implements Exception {
  const AiChatCancelledException();

  @override
  String toString() => '生成已停止。';
}

enum _ChatBackendType { local, external }

class _ActiveChatOperation {
  _ResolvedChatBackend? backend;
  bool cancelled = false;
}

class _ResolvedChatBackend {
  const _ResolvedChatBackend.local({
    required this.llmEngine,
    required this.llmModel,
    required this.reason,
  }) : type = _ChatBackendType.local,
       externalGateway = null,
       externalAuthorization = null;

  const _ResolvedChatBackend.external({
    required this.externalGateway,
    required this.externalAuthorization,
    required this.reason,
  }) : type = _ChatBackendType.external,
       llmEngine = null,
       llmModel = null;

  final _ChatBackendType type;
  final String reason;
  final LlmEngine? llmEngine;
  final ModelRegistryEntry? llmModel;
  final ExternalChatGateway? externalGateway;
  final ExternalChatAuthorization? externalAuthorization;
}

class _GeneratedChatResponse {
  const _GeneratedChatResponse({required this.text, required this.usage});

  final String text;
  final ChatBackendUsage usage;
}
