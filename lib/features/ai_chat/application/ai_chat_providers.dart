import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
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

part 'ai_chat_conversation_state.dart';
part 'ai_chat_conversation_controller.dart';
part 'ai_chat_conversation_selection.dart';
part 'ai_chat_conversation_mapping.dart';
part 'ai_chat_sensitive_providers.dart';

final aiChatContextRetrieverProvider = Provider<AiChatContextRetriever>((ref) {
  return SemanticAiChatContextRetriever(ref: ref);
});

final aiChatOrchestratorProvider = Provider<AiChatOrchestrator>((ref) {
  return AiChatOrchestrator(ref: ref);
});

final privateQaChatControllerProvider =
    StateNotifierProvider<
      AiChatConversationController,
      AiChatConversationState
    >((ref) {
      return AiChatConversationController(ref: ref, mode: ChatMode.privateQa);
    });

final freeChatControllerProvider =
    StateNotifierProvider<
      AiChatConversationController,
      AiChatConversationState
    >((ref) {
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
    final results = await _ref
        .read(semanticSearchServiceProvider)
        .search(
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

    final backend = await _resolveBackend(request.backendPreference);

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

  Future<_ResolvedChatBackend> _resolveBackend(
    ChatBackendPreference preference,
  ) async {
    return switch (preference) {
      ChatBackendPreference.local => _resolveLocalBackend(),
      ChatBackendPreference.external => _resolveExternalBackend(),
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

  Future<_ResolvedChatBackend> _resolveExternalBackend() async {
    final externalStatus = await _ref.read(
      externalProviderStatusProvider.future,
    );
    if (!externalStatus.available || externalStatus.config == null) {
      throw StateError(externalStatus.reason);
    }
    final config = externalStatus.config!;
    final acknowledged = await _ref
        .read(externalPrivacyConfirmationControllerProvider)
        .hasAcknowledged(config);
    if (!acknowledged) {
      throw StateError('外部模型配置尚未确认。');
    }
    return _ResolvedChatBackend.external(
      externalConfig: config,
      externalClient: _ref.read(externalProviderClientProvider),
      reason: externalStatus.reason,
    );
  }

  Future<AiChatResponse> _runPrivateQa({
    required String userInput,
    required AiChatRequest request,
    required _ResolvedChatBackend backend,
  }) async {
    _validateExternalPrivateContext(
      backend: backend,
      usedPrivateContext: false,
      requestedPrivateContext: true,
    );
    final semanticReadiness = await _ref.read(
      semanticSearchReadinessProvider.future,
    );
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
    final usedPrivateContext = contextItems.isNotEmpty;
    _validateExternalPrivateContext(
      backend: backend,
      usedPrivateContext: usedPrivateContext,
      requestedPrivateContext:
          request.allowPrivateContext || usedPrivateContext,
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
    required AiChatRequest request,
    required _ResolvedChatBackend backend,
  }) async {
    final manualItems = request.allowPrivateContext
        ? _dedupeContextItems(request.manualItems)
        : const <ChatContextItem>[];
    var autoItems = const <ChatContextItem>[];

    if (request.allowPrivateContext) {
      final semanticReadiness = await _ref.read(
        semanticSearchReadinessProvider.future,
      );
      if (semanticReadiness.ready &&
          semanticReadiness.activeEmbeddingModel != null) {
        autoItems = await _ref
            .read(aiChatContextRetrieverProvider)
            .retrieve(
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
      )).text,
      _ChatBackendType.external =>
        backend.externalClient!.generateChatCompletion(
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
  }) : type = _ChatBackendType.local,
       externalConfig = null,
       externalClient = null;

  const _ResolvedChatBackend.external({
    required this.externalConfig,
    required this.externalClient,
    required this.reason,
  }) : type = _ChatBackendType.external,
       llmEngine = null,
       llmModel = null;

  final _ChatBackendType type;
  final String reason;
  final LlmEngine? llmEngine;
  final ModelRegistryEntry? llmModel;
  final ExternalProviderConfig? externalConfig;
  final ExternalProviderClient? externalClient;
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
