import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:uuid/uuid.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_message.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

final aiChatContextRetrieverProvider = Provider<AiChatContextRetriever>((ref) {
  return SemanticAiChatContextRetriever(ref: ref);
});

final aiChatOrchestratorProvider = Provider<AiChatOrchestrator>((ref) {
  return AiChatOrchestrator(ref: ref);
});

final freeChatSemanticReadinessProvider = FutureProvider<SemanticSearchReadiness>((ref) async {
  return ref.watch(semanticSearchReadinessProvider.future);
});

final privateQaSemanticReadinessProvider = FutureProvider<SemanticSearchReadiness>((ref) async {
  return ref.watch(semanticSearchReadinessProvider.future);
});

final manualContextCandidatesProvider = FutureProvider<List<ChatContextItem>>((ref) async {
  final secrets = await ref.watch(secretListProvider.future);
  final notes = await ref.watch(noteListProvider.future);
  return [..._mapSecretsToContextItems(secrets), ..._mapNotesToContextItems(notes)];
});

final privateQaChatControllerProvider =
    StateNotifierProvider<AiChatConversationController, AiChatConversationState>((ref) {
  return AiChatConversationController(ref: ref, mode: ChatMode.privateQa);
});

final freeChatControllerProvider =
    StateNotifierProvider<AiChatConversationController, AiChatConversationState>((ref) {
  return AiChatConversationController(ref: ref, mode: ChatMode.freeChat);
});

abstract interface class AiChatContextRetriever {
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required ModelRegistryEntry embeddingModel,
  });
}

class SemanticAiChatContextRetriever implements AiChatContextRetriever {
  const SemanticAiChatContextRetriever({required Ref ref}) : _ref = ref;

  final Ref _ref;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required ModelRegistryEntry embeddingModel,
  }) async {
    final scope = await _ref.read(searchScopeConfigProvider.future);
    final secrets = await _ref.read(secretListProvider.future);
    final notes = await _ref.read(noteListProvider.future);
    final results = await _ref.read(semanticSearchServiceProvider).search(
          query: query,
          scope: scope,
          activeEmbeddingModel: embeddingModel,
          secrets: secrets,
          notes: notes,
        );

    return results
        .map(
          (result) => ChatContextItem(
            id: result.item.id,
            type: result.item.type == SearchResultType.secret
                ? ChatContextItemType.secret
                : ChatContextItemType.note,
            title: result.item.title,
            preview: result.item.preview,
            summary: result.hitSummary,
            semanticHitField: result.hitField,
          ),
        )
        .toList(growable: false);
  }
}

class AiChatOrchestrator {
  const AiChatOrchestrator({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<AiChatResponse> send(AiChatRequest request) async {
    final userInput = request.userInput.trim();
    if (userInput.isEmpty) {
      throw StateError('请输入问题或消息。');
    }

    final backend = await _resolveBackend();

    return switch (request.mode) {
      ChatMode.privateQa => _runPrivateQa(
          userInput: userInput,
          request: request,
          backend: backend,
        ),
      ChatMode.freeChat => _runFreeChat(
          userInput: userInput,
          request: request,
          backend: backend,
        ),
    };
  }

  Future<_ResolvedChatBackend> _resolveBackend() async {
    final llmReadiness = await _ref.read(localLlmReadinessProvider.future);
    if (llmReadiness.ready && llmReadiness.activeModel != null) {
      return _ResolvedChatBackend.local(
        llmEngine: _ref.read(llmEngineProvider),
        llmModel: llmReadiness.activeModel!,
        reason: llmReadiness.reason,
      );
    }

    final externalStatus = await _ref.read(externalProviderStatusProvider.future);
    if (externalStatus.available && externalStatus.config != null) {
      return _ResolvedChatBackend.external(
        externalConfig: externalStatus.config!,
        externalClient: _ref.read(externalProviderClientProvider),
        reason: externalStatus.reason,
      );
    }

    throw StateError(llmReadiness.reason);
  }

  Future<AiChatResponse> _runPrivateQa({
    required String userInput,
    required AiChatRequest request,
    required _ResolvedChatBackend backend,
  }) async {
    final semanticReadiness = await _ref.read(semanticSearchReadinessProvider.future);
    if (!semanticReadiness.ready || semanticReadiness.activeEmbeddingModel == null) {
      throw StateError(semanticReadiness.reason);
    }

    final contextItems = await _ref.read(aiChatContextRetrieverProvider).retrieve(
          query: userInput,
          embeddingModel: semanticReadiness.activeEmbeddingModel!,
        );
    final usedPrivateContext = contextItems.isNotEmpty;
    _validateExternalPrivateContext(
      backend: backend,
      usedPrivateContext: usedPrivateContext,
      requestedPrivateContext: request.allowPrivateContext || usedPrivateContext,
    );
    final prompt = _buildPrompt(
      mode: ChatMode.privateQa,
      userInput: userInput,
      contextItems: contextItems,
    );
    final text = await _generateText(
      backend: backend,
      prompt: prompt,
      usedPrivateContext: usedPrivateContext,
    );

    return AiChatResponse(
      text: text,
      contextSummary: contextItems.map((item) => item.summary).toList(growable: false),
      usedPrivateContext: usedPrivateContext,
      sourceType: usedPrivateContext ? ChatContextSource.autoRetrieved : ChatContextSource.none,
      contextItems: contextItems,
    );
  }

  Future<AiChatResponse> _runFreeChat({
    required String userInput,
    required AiChatRequest request,
    required _ResolvedChatBackend backend,
  }) async {
    final manualItems = _dedupeContextItems(request.manualItems);
    var autoItems = const <ChatContextItem>[];

    if (request.allowPrivateContext) {
      final semanticReadiness = await _ref.read(semanticSearchReadinessProvider.future);
      if (semanticReadiness.ready && semanticReadiness.activeEmbeddingModel != null) {
        autoItems = await _ref.read(aiChatContextRetrieverProvider).retrieve(
              query: userInput,
              embeddingModel: semanticReadiness.activeEmbeddingModel!,
            );
      }
    }

    final contextItems = _dedupeContextItems([...autoItems, ...manualItems]);
    final usedPrivateContext = contextItems.isNotEmpty;
    _validateExternalPrivateContext(
      backend: backend,
      usedPrivateContext: usedPrivateContext,
      requestedPrivateContext: request.allowPrivateContext,
    );
    final prompt = _buildPrompt(
      mode: ChatMode.freeChat,
      userInput: userInput,
      contextItems: contextItems,
    );
    final text = await _generateText(
      backend: backend,
      prompt: prompt,
      usedPrivateContext: usedPrivateContext,
    );

    return AiChatResponse(
      text: text,
      contextSummary: contextItems.map((item) => item.summary).toList(growable: false),
      usedPrivateContext: usedPrivateContext,
      sourceType: _resolveSourceType(autoItems: autoItems, manualItems: manualItems),
      contextItems: contextItems,
    );
  }

  Future<String> _generateText({
    required _ResolvedChatBackend backend,
    required String prompt,
    required bool usedPrivateContext,
  }) async {
    return switch (backend.type) {
      _ChatBackendType.local => (await backend.llmEngine!.generate(
          LlmInferenceRequest(
            model: backend.llmModel!,
            prompt: prompt,
            usedPrivateContext: usedPrivateContext,
          ),
        ))
          .text,
      _ChatBackendType.external => backend.externalClient!.generateChatCompletion(
          config: backend.externalConfig!,
          prompt: prompt,
          usedPrivateContext: usedPrivateContext,
        ),
    };
  }

  void _validateExternalPrivateContext({
    required _ResolvedChatBackend backend,
    required bool usedPrivateContext,
    required bool requestedPrivateContext,
  }) {
    if (backend.type != _ChatBackendType.external) {
      return;
    }
    if (!usedPrivateContext && !requestedPrivateContext) {
      return;
    }
    if (backend.externalConfig!.allowSensitiveFields) {
      return;
    }
    throw StateError('当前外部模型未允许访问私密内容。');
  }

  String _buildPrompt({
    required ChatMode mode,
    required String userInput,
    required List<ChatContextItem> contextItems,
  }) {
    if (contextItems.isEmpty) {
      return userInput;
    }

    final contextBlock = contextItems
        .map((item) => '- ${item.title}：${item.summary}')
        .join('\n');
    final intro = switch (mode) {
      ChatMode.privateQa => '请基于以下本地私密内容回答用户问题。',
      ChatMode.freeChat => '如上下文有帮助，请结合以下本地私密内容回答。',
    };

    return '$intro\n\n可用上下文：\n$contextBlock\n\n用户输入：$userInput';
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

  List<ChatContextItem> _dedupeContextItems(List<ChatContextItem> items) {
    final deduped = <ChatContextItem>[];
    final seen = <String>{};
    for (final item in items) {
      if (seen.add(item.id)) {
        deduped.add(item);
      }
    }
    return deduped;
  }
}

enum _ChatBackendType { local, external }

class _ResolvedChatBackend {
  const _ResolvedChatBackend.local({
    required this.llmEngine,
    required this.llmModel,
    required this.reason,
  })  : type = _ChatBackendType.local,
        externalConfig = null,
        externalClient = null;

  const _ResolvedChatBackend.external({
    required this.externalConfig,
    required this.externalClient,
    required this.reason,
  })  : type = _ChatBackendType.external,
        llmEngine = null,
        llmModel = null;

  final _ChatBackendType type;
  final String reason;
  final LlmEngine? llmEngine;
  final ModelRegistryEntry? llmModel;
  final ExternalProviderConfig? externalConfig;
  final ExternalProviderClient? externalClient;
}

class AiChatConversationState {
  const AiChatConversationState({
    required this.mode,
    this.messages = const <ChatMessage>[],
    this.sending = false,
    this.allowPrivateContext = false,
    this.manualItems = const <ChatContextItem>[],
    this.currentSessionId,
    this.errorMessage,
    this.suppressSessionRestore = false,
  });

  final ChatMode mode;
  final List<ChatMessage> messages;
  final bool sending;
  final bool allowPrivateContext;
  final List<ChatContextItem> manualItems;
  final String? currentSessionId;
  final String? errorMessage;
  final bool suppressSessionRestore;

  AiChatConversationState copyWith({
    ChatMode? mode,
    List<ChatMessage>? messages,
    bool? sending,
    bool? allowPrivateContext,
    List<ChatContextItem>? manualItems,
    String? currentSessionId,
    bool clearCurrentSessionId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? suppressSessionRestore,
  }) {
    return AiChatConversationState(
      mode: mode ?? this.mode,
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
      allowPrivateContext: allowPrivateContext ?? this.allowPrivateContext,
      manualItems: manualItems ?? this.manualItems,
      currentSessionId: clearCurrentSessionId ? null : (currentSessionId ?? this.currentSessionId),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      suppressSessionRestore: suppressSessionRestore ?? this.suppressSessionRestore,
    );
  }
}

class AiChatConversationController extends StateNotifier<AiChatConversationState> {
  AiChatConversationController({required Ref ref, required ChatMode mode})
      : _ref = ref,
        super(AiChatConversationState(mode: mode));

  final Ref _ref;
  final AppLogger _logger = const AppLogger();
  static const _uuid = Uuid();

  Future<void> restoreSessionIfNeeded() async {
    final selectedSessionId = _ref.read(currentChatSessionIdProvider);
    if (selectedSessionId != null && selectedSessionId.isNotEmpty) {
      if (state.currentSessionId != selectedSessionId) {
        await selectSession(selectedSessionId);
      }
      return;
    }

    if (state.currentSessionId != null && state.messages.isNotEmpty) {
      return;
    }

    if (state.suppressSessionRestore) {
      return;
    }

    final sessions = await _ref.read(chatSessionsProvider.future);
    final matchingSession = sessions.where((session) => session.mode == state.mode).firstOrNull;
    if (matchingSession == null) {
      return;
    }

    await selectSession(matchingSession.id);
  }

  Future<void> selectSession(String sessionId) async {
    final repository = _ref.read(chatSessionRepositoryProvider);
    final messages = await repository.listMessages(sessionId);
    final session = await repository.getSession(sessionId);

    _ref.read(suppressRestoredChatSessionProvider.notifier).state = false;

    state = state.copyWith(
      currentSessionId: sessionId,
      allowPrivateContext: session?.allowPrivateContext ?? state.allowPrivateContext,
      messages: messages.map(_mapStoredMessageToUi).toList(growable: false),
      clearErrorMessage: true,
      suppressSessionRestore: false,
    );

    if (_ref.read(currentChatSessionIdProvider) != sessionId) {
      _ref.read(currentChatSessionIdProvider.notifier).state = sessionId;
    }
    _ref.invalidate(currentChatMessagesProvider);
    _ref.invalidate(currentChatSessionProvider);
  }

  Future<void> startNewSession() async {
    _ref.read(suppressRestoredChatSessionProvider.notifier).state = true;
    _ref.read(currentChatSessionIdProvider.notifier).state = null;
    state = state.copyWith(
      messages: const <ChatMessage>[],
      clearCurrentSessionId: true,
      clearErrorMessage: true,
      suppressSessionRestore: true,
    );
    _ref.invalidate(currentChatMessagesProvider);
    _ref.invalidate(currentChatSessionProvider);
  }

  Future<void> send(String input) async {
    final normalized = input.trim();
    if (normalized.isEmpty || state.sending) {
      return;
    }

    final repository = _ref.read(chatSessionRepositoryProvider);
    final llmReadiness = await _ref.read(localLlmReadinessProvider.future);
    final timestamp = DateTime.now();
    final sessionId = state.currentSessionId ?? _uuid.v4();
    final correlationId = timestamp.microsecondsSinceEpoch;
    final sessionTitle = normalized.length <= 20 ? normalized : '${normalized.substring(0, 20)}…';

    _logger.info(
      '[ai_chat_send] event=start correlation_id=$correlationId '
      'session_id=$sessionId mode=${state.mode.name} input_len=${normalized.length}',
    );

    final session = ChatSession(
      id: sessionId,
      mode: state.mode,
      title: sessionTitle,
      allowPrivateContext: state.allowPrivateContext,
      lastModelId: llmReadiness.activeModel?.id,
      archived: false,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final userMessage = ChatMessage(
      id: 'user-${timestamp.microsecondsSinceEpoch}',
      role: ChatMessageRole.user,
      text: normalized,
      createdAt: timestamp,
    );
    final loadingMessage = ChatMessage(
      id: 'assistant-${timestamp.microsecondsSinceEpoch}',
      role: ChatMessageRole.assistant,
      text: '正在生成回答…',
      createdAt: timestamp,
      status: ChatMessageStatus.loading,
    );

    await repository.saveSession(session);
    await repository.saveMessage(
      ChatStoredMessage(
        id: userMessage.id,
        sessionId: sessionId,
        role: ChatStoredMessageRole.user,
        content: userMessage.text,
        status: ChatStoredMessageStatus.completed,
        createdAt: userMessage.createdAt,
      ),
    );
    _logger.info(
      '[ai_chat_send] event=user_saved correlation_id=$correlationId '
      'message_id=${userMessage.id}',
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage, loadingMessage],
      sending: true,
      currentSessionId: sessionId,
      clearErrorMessage: true,
      suppressSessionRestore: false,
    );

    _ref.read(suppressRestoredChatSessionProvider.notifier).state = false;
    _ref.read(currentChatSessionIdProvider.notifier).state = sessionId;

    try {
      final response = await _ref.read(aiChatOrchestratorProvider).send(
            AiChatRequest(
              mode: state.mode,
              userInput: normalized,
              allowPrivateContext: state.allowPrivateContext,
              manualItems: state.manualItems,
            ),
          );
      final assistantMessage = ChatMessage(
        id: loadingMessage.id,
        role: ChatMessageRole.assistant,
        text: response.text,
        createdAt: DateTime.now(),
        status: ChatMessageStatus.completed,
        usedPrivateContext: response.usedPrivateContext,
        contextSummary: response.contextSummary,
        sourceType: response.sourceType,
      );
      await repository.saveSession(
        session.copyWith(
          title: sessionTitle,
          allowPrivateContext: state.allowPrivateContext,
          lastModelId: llmReadiness.activeModel?.id,
          updatedAt: assistantMessage.createdAt,
        ),
      );
      await repository.saveMessage(
        ChatStoredMessage(
          id: assistantMessage.id,
          sessionId: sessionId,
          role: ChatStoredMessageRole.assistant,
          content: assistantMessage.text,
          status: ChatStoredMessageStatus.completed,
          usedPrivateContext: assistantMessage.usedPrivateContext,
          autoRetrievedContextSummary: assistantMessage.contextSummary.isEmpty
              ? null
              : assistantMessage.contextSummary.join('；'),
          manualContextItemIds: state.manualItems.map((item) => item.id).toList(growable: false),
          relatedSourceIds: response.contextItems.map((item) => item.id).toList(growable: false),
          createdAt: assistantMessage.createdAt,
        ),
      );
      _logger.info(
        '[ai_chat_send] event=assistant_saved correlation_id=$correlationId '
        'message_id=${assistantMessage.id} status=completed',
      );
      state = state.copyWith(
        messages: _replaceMessageById(
          messages: state.messages,
          targetId: loadingMessage.id,
          replacement: assistantMessage,
        ),
        sending: false,
      );
      _ref.invalidate(chatSessionsProvider);
      _ref.invalidate(currentChatMessagesProvider);
      _ref.invalidate(currentChatSessionProvider);
    } catch (error) {
      final failedMessage = ChatMessage(
        id: loadingMessage.id,
        role: ChatMessageRole.system,
        text: error.toString().replaceFirst('Bad state: ', ''),
        createdAt: DateTime.now(),
        status: ChatMessageStatus.error,
      );
      await repository.saveSession(
        session.copyWith(
          title: sessionTitle,
          allowPrivateContext: state.allowPrivateContext,
          lastModelId: llmReadiness.activeModel?.id,
          updatedAt: failedMessage.createdAt,
        ),
      );
      await repository.saveMessage(
        ChatStoredMessage(
          id: failedMessage.id,
          sessionId: sessionId,
          role: ChatStoredMessageRole.system,
          content: failedMessage.text,
          status: ChatStoredMessageStatus.failed,
          createdAt: failedMessage.createdAt,
        ),
      );
      _logger.info(
        '[ai_chat_send] event=assistant_saved correlation_id=$correlationId '
        'message_id=${failedMessage.id} status=failed',
      );
      state = state.copyWith(
        messages: _replaceMessageById(
          messages: state.messages,
          targetId: loadingMessage.id,
          replacement: failedMessage,
        ),
        sending: false,
        errorMessage: failedMessage.text,
      );
      _ref.invalidate(chatSessionsProvider);
      _ref.invalidate(currentChatMessagesProvider);
      _ref.invalidate(currentChatSessionProvider);
    }
  }

  void setAllowPrivateContext(bool value) {
    state = state.copyWith(allowPrivateContext: value);
  }

  void setManualItems(List<ChatContextItem> items) {
    state = state.copyWith(manualItems: items);
  }

  List<ChatMessage> _replaceMessageById({
    required List<ChatMessage> messages,
    required String targetId,
    required ChatMessage replacement,
  }) {
    final index = messages.indexWhere((message) => message.id == targetId);
    if (index == -1) {
      return [...messages, replacement];
    }

    return [
      ...messages.take(index),
      replacement,
      ...messages.skip(index + 1),
    ];
  }

  ChatMessage _mapStoredMessageToUi(ChatStoredMessage message) {
    return ChatMessage(
      id: message.id,
      role: switch (message.role) {
        ChatStoredMessageRole.user => ChatMessageRole.user,
        ChatStoredMessageRole.assistant => ChatMessageRole.assistant,
        ChatStoredMessageRole.system => ChatMessageRole.system,
      },
      text: message.content,
      createdAt: message.createdAt,
      status: switch (message.status) {
        ChatStoredMessageStatus.loading => ChatMessageStatus.loading,
        ChatStoredMessageStatus.completed => ChatMessageStatus.completed,
        ChatStoredMessageStatus.failed => ChatMessageStatus.error,
      },
      usedPrivateContext: message.usedPrivateContext,
      contextSummary: message.autoRetrievedContextSummary == null ||
              message.autoRetrievedContextSummary!.trim().isEmpty
          ? const <String>[]
          : message.autoRetrievedContextSummary!.split('；'),
    );
  }
}

List<ChatContextItem> _mapSecretsToContextItems(List<SecretItem> secrets) {
  return secrets
      .map(
        (item) => ChatContextItem(
          id: item.id,
          type: ChatContextItemType.secret,
          title: item.title,
          preview: item.tags.isEmpty ? '私密条目' : item.tags.join('、'),
          summary: '手动选择的私密条目：${item.title}',
        ),
      )
      .toList(growable: false);
}

List<ChatContextItem> _mapNotesToContextItems(List<NoteItem> notes) {
  return notes
      .map(
        (item) => ChatContextItem(
          id: item.id,
          type: ChatContextItemType.note,
          title: item.title,
          preview: item.tags.isEmpty ? '私密笔记' : item.tags.join('、'),
          summary: '手动选择的私密笔记：${item.title}',
        ),
      )
      .toList(growable: false);
}
