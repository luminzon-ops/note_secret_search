import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:uuid/uuid.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_context_projector.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_prompt_composer.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/external_chat_gateway.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_backend_usage.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_policy.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_message.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/application/semantic_quality_policy.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

part 'ai_chat_conversation_state.dart';
part 'ai_chat_conversation_controller.dart';
part 'ai_chat_conversation_selection.dart';
part 'ai_chat_conversation_mapping.dart';
part 'ai_chat_orchestrator.dart';
part 'ai_chat_sensitive_providers.dart';

final aiChatContextRetrieverProvider = Provider<AiChatContextRetriever>((ref) {
  return SemanticAiChatContextRetriever(ref: ref);
});

final chatContextProjectorProvider = Provider<ChatContextProjector>((ref) {
  return RepositoryChatContextProjector(
    secretRepository: ref.watch(secretRepositoryProvider),
    noteRepository: ref.watch(noteRepositoryProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
  );
});

final chatPromptComposerProvider = Provider<ChatPromptComposer>((ref) {
  return const ChatPromptComposer();
});

final aiChatOrchestratorProvider = Provider<AiChatOrchestrator>((ref) {
  return AiChatOrchestrator(
    loadLocalReadiness: () => ref.read(localLlmReadinessProvider.future),
    loadLlmEngine: () => ref.read(llmEngineProvider),
    loadExternalGateway: () => ref.read(externalChatGatewayProvider),
    loadSemanticReadiness: () =>
        ref.read(semanticSearchReadinessProvider.future),
    loadContextRetriever: () => ref.read(aiChatContextRetrieverProvider),
    loadSearchConfiguration: () => ref.read(searchConfigurationProvider.future),
    loadContextProjector: () => ref.read(chatContextProjectorProvider),
    loadPromptComposer: () => ref.read(chatPromptComposerProvider),
  );
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
  const SemanticAiChatContextRetriever({
    required Ref ref,
    SemanticQualityPolicy qualityPolicy =
        const SemanticQualityPolicy.conservativeMvp(),
  }) : _ref = ref,
       _qualityPolicy = qualityPolicy;

  final Ref _ref;
  final SemanticQualityPolicy _qualityPolicy;

  @override
  Future<List<ChatContextItem>> retrieve({
    required String query,
    required ModelRegistryEntry embeddingModel,
  }) async {
    final configuration = await _ref.read(searchConfigurationProvider.future);
    final vault = await _ref.read(defaultVaultProvider.future);
    if (vault == null) {
      return const <ChatContextItem>[];
    }
    final modelRevisionHash = await _ref.read(
      searchIndexModelRevisionProvider(embeddingModel).future,
    );
    final results = await _ref
        .read(semanticSearchServiceProvider)
        .searchCorpus(
          activeVaultId: vault.id,
          query: query,
          configuration: configuration,
          modelRevisionHash: modelRevisionHash,
          activeEmbeddingModel: embeddingModel,
          corpus: _ref.read(searchCorpusReaderProvider),
          operation: SearchOperation.aiAutoContext,
        );

    return normalizeChatContextItems(
      results
          .where(_admitsAutoContext)
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
          ),
    );
  }

  bool _admitsAutoContext(SemanticSearchResult result) {
    return _qualityPolicy.admitsSemanticOnly(
      fieldQualityTier: result.fieldQualityTier,
      aggregateRankingScore: result.score,
    );
  }
}
