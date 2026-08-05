import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/settings/application/secure_clipboard_providers.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';

final sensitiveStateInvalidatorProvider = Provider<SensitiveStateInvalidator>((
  ref,
) {
  return SensitiveStateInvalidator(ref: ref);
});

class SensitiveStateInvalidator {
  SensitiveStateInvalidator({required Ref ref}) : _ref = ref;

  final Ref _ref;

  void clearForLock() {
    unawaited(_ref.read(secureClipboardControllerProvider).clearForLock());

    if (_ref.read(sensitiveStateAccessAllowedProvider)) {
      _ref.read(sensitiveStateAccessAllowedProvider.notifier).state = false;
    }

    _ref.read(privateQaChatControllerProvider.notifier).resetForLock();
    _ref.read(freeChatControllerProvider.notifier).resetForLock();

    _ref.read(searchQueryProvider.notifier).state = '';
    _ref.read(searchRefreshControllerProvider.notifier).resetForLock();

    _ref.invalidate(defaultVaultProvider);
    _ref.invalidate(secretListProvider);
    _ref.invalidate(secretDetailProvider);
    _ref.invalidate(noteListProvider);
    _ref.invalidate(noteDetailProvider);

    _ref.invalidate(keywordSearchResultsProvider);
    _ref.invalidate(semanticSearchResultsProvider);
    _ref.invalidate(unifiedSearchResultsProvider);
    _ref.invalidate(searchIndexStatusSnapshotProvider);
    _ref.invalidate(searchIndexStatusProvider);

    _ref.invalidate(chatSessionsProvider);
    _ref.invalidate(restoredChatSessionIdProvider);
    _ref.invalidate(currentChatSessionProvider);
    _ref.invalidate(currentChatMessagesProvider);
    _ref.invalidate(manualContextCandidatesProvider);
    _ref.invalidate(freeChatSemanticReadinessProvider);
    _ref.invalidate(privateQaSemanticReadinessProvider);

    _ref.invalidate(enabledExternalProviderProvider);
    _ref.invalidate(externalProviderStatusProvider);
    _ref.invalidate(externalProviderClientRouterProvider);

    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(modelDownloadTasksProvider);
    _ref.invalidate(embeddingRuntimeStatesProvider);
    _ref.invalidate(activeModelSelectionProvider);
    _ref.invalidate(activeEmbeddingRuntimeSelectionProvider);
    _ref.invalidate(activeEmbeddingModelProvider);
    _ref.invalidate(semanticSearchReadinessProvider);
    _ref.invalidate(llmRuntimeStatesProvider);
    _ref.invalidate(activeLocalLlmModelProvider);
    _ref.invalidate(localLlmReadinessProvider);
  }

  void allowSensitiveStateAccess() {
    if (!_ref.read(sensitiveStateAccessAllowedProvider)) {
      _ref.read(sensitiveStateAccessAllowedProvider.notifier).state = true;
    }
  }
}
