part of 'ai_chat_providers.dart';

class AiChatConversationController
    extends StateNotifier<AiChatConversationState>
    with _AiChatConversationSelection {
  AiChatConversationController({required Ref ref, required ChatMode mode})
    : _ref = ref,
      _orchestrator = ref.read(aiChatOrchestratorProvider),
      super(AiChatConversationState(mode: mode));

  @override
  final Ref _ref;
  final AiChatOrchestrator _orchestrator;
  static const _uuid = Uuid();
  final Map<String, _SendingChatOperation> _sendingOperations =
      <String, _SendingChatOperation>{};
  @override
  var _generation = 0;

  Future<void> restoreSessionIfNeeded() async {
    final generation = _generation;
    final startingIntent = _ref.read(chatSessionSelectionIntentProvider);
    final startingAttempt = _ref.read(chatSessionSelectionAttemptProvider);
    if (!_restoreCanContinue(generation, startingIntent) ||
        _hasPendingSelectionAttempt) {
      return;
    }
    if (startingIntent.revision > 0 && startingIntent.sessionId == null) {
      return;
    }

    final selectedSessionId = _ref.read(currentChatSessionIdProvider);
    if (selectedSessionId != null && selectedSessionId.isNotEmpty) {
      if (!_intentAllowsTarget(startingIntent, selectedSessionId)) {
        return;
      }
      if (state.currentSessionId != selectedSessionId) {
        await _selectSession(selectedSessionId, generation, startingIntent);
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
    if (!_restoreCanContinue(generation, startingIntent) ||
        !_selectionAttemptIsCurrent(startingAttempt) ||
        _hasPendingSelectionAttempt) {
      return;
    }
    final newestSession = sessions.firstOrNull;
    if (newestSession == null || newestSession.mode != state.mode) {
      return;
    }

    final restoreIntent = _claimSelectionIntent(newestSession.id);
    await _selectSession(newestSession.id, generation, restoreIntent);
  }

  Future<void> selectSession(String sessionId) async {
    final selectionAttempt = _claimSelectionAttempt();
    final generation = _generation;
    try {
      if (!_canContinue(generation)) {
        return;
      }
      final startingIntent = _ref.read(chatSessionSelectionIntentProvider);
      final repository = _ref.read(chatSessionRepositoryProvider);
      final messages = await repository.listMessages(sessionId);
      if (!_canContinue(generation) ||
          !_selectionAttemptIsCurrent(selectionAttempt) ||
          !_intentIsCurrent(startingIntent)) {
        return;
      }
      final session = await repository.getSession(sessionId);
      if (!_canContinue(generation) ||
          !_selectionAttemptIsCurrent(selectionAttempt) ||
          !_intentIsCurrent(startingIntent) ||
          session == null ||
          session.mode != state.mode) {
        return;
      }
      final intent = _claimSelectionIntent(sessionId);
      await _selectSession(
        sessionId,
        generation,
        intent,
        validatedSession: session,
        validatedMessages: messages,
      );
    } finally {
      _completeSelectionAttempt(selectionAttempt);
    }
  }

  Future<void> _selectSession(
    String sessionId,
    int generation,
    ChatSessionSelectionIntent intent, {
    ChatSession? validatedSession,
    List<ChatStoredMessage>? validatedMessages,
  }) async {
    if (!_selectionCanContinue(generation, intent, sessionId)) {
      return;
    }
    final repository = _ref.read(chatSessionRepositoryProvider);
    final messages =
        validatedMessages ?? await repository.listMessages(sessionId);
    if (!_selectionCanContinue(generation, intent, sessionId)) {
      return;
    }
    final session = validatedSession ?? await repository.getSession(sessionId);
    if (!_selectionCanContinue(generation, intent, sessionId)) {
      return;
    }
    if (session == null || session.mode != state.mode) {
      return;
    }

    _ref.read(suppressRestoredChatSessionProvider.notifier).state = false;
    state = state.copyWith(
      currentSessionId: sessionId,
      backendPreference: ChatBackendPreference.local,
      allowPrivateContext: session.allowPrivateContext,
      manualItems: const <ChatContextItem>[],
      messages: messages.map(_mapStoredChatMessageToUi).toList(growable: false),
      sending: _sendingOperations.containsKey(sessionId),
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
    _cancelPendingSelectionAttempts();
    _generation++;
    await _cancelActiveRequests();
    _claimSelectionIntent(null);
    _resetConversation();
  }

  void resetForLock() {
    _cancelPendingSelectionAttempts();
    _generation++;
    unawaited(_cancelActiveRequests());
    _claimSelectionIntent(null);
    _resetConversation();
  }

  Future<void> stopGeneration() => _cancelActiveRequests();

  @override
  void dispose() {
    _generation++;
    unawaited(_cancelActiveRequests());
    super.dispose();
  }

  void _resetConversation() {
    _sendingOperations.clear();
    _ref.read(suppressRestoredChatSessionProvider.notifier).state = true;
    _ref.read(currentChatSessionIdProvider.notifier).state = null;
    state = AiChatConversationState(
      mode: state.mode,
      suppressSessionRestore: true,
    );
    _ref.invalidate(currentChatMessagesProvider);
    _ref.invalidate(currentChatSessionProvider);
  }

  Future<void> send(String input) async {
    final normalized = input.trim();
    final generation = _generation;
    if (normalized.isEmpty || !_canContinue(generation)) {
      return;
    }

    final conversationMode = state.mode;
    final backendPreference = state.backendPreference;
    final allowPrivateContext = state.allowPrivateContext;
    final history = _buildChatHistory(state.messages);
    final manualItems = List<ChatContextItem>.of(
      state.manualItems,
      growable: false,
    );
    final existingSessionId = state.currentSessionId;
    final originSessionId = existingSessionId ?? _uuid.v4();
    final publicationIntent = existingSessionId == null
        ? _ref.read(chatSessionSelectionIntentProvider)
        : null;
    final publicationSessionId = existingSessionId == null
        ? _ref.read(currentChatSessionIdProvider)
        : null;
    final publicationAttempt = existingSessionId == null
        ? _ref.read(chatSessionSelectionAttemptProvider)
        : null;
    if (_sendingOperations.containsKey(originSessionId)) {
      return;
    }
    if (existingSessionId != null) {
      _activateExistingOriginSession(originSessionId);
    }
    final sendingOperation = _SendingChatOperation(requestId: _uuid.v4());
    _sendingOperations[originSessionId] = sendingOperation;

    try {
      final repository = _ref.read(chatSessionRepositoryProvider);
      if (backendPreference == ChatBackendPreference.local) {
        await _ref.read(localLlmReadinessProvider.future);
      }
      final existingSession = existingSessionId == null
          ? null
          : await repository.getSession(originSessionId);
      if (!_canContinue(generation)) {
        return;
      }
      final timestamp = DateTime.now();
      final sessionTitle =
          existingSession?.title ??
          (normalized.length <= 20
              ? normalized
              : '${normalized.substring(0, 20)}…');

      final session =
          existingSession?.copyWith(
            allowPrivateContext: allowPrivateContext,
            updatedAt: timestamp,
          ) ??
          ChatSession(
            id: originSessionId,
            mode: conversationMode,
            title: sessionTitle,
            allowPrivateContext: allowPrivateContext,
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
      if (!_canContinue(generation)) {
        return;
      }
      if (publicationIntent != null &&
          _canPublishNewOrigin(
            publicationIntent,
            publicationSessionId,
            publicationAttempt!,
          )) {
        _publishNewOriginSession(originSessionId);
      }
      await repository.saveMessage(
        ChatStoredMessage(
          id: userMessage.id,
          sessionId: originSessionId,
          role: ChatStoredMessageRole.user,
          content: userMessage.text,
          status: ChatStoredMessageStatus.completed,
          createdAt: userMessage.createdAt,
        ),
      );
      if (!_canContinue(generation)) {
        return;
      }

      if (_isOriginSelected(originSessionId, conversationMode)) {
        state = state.copyWith(
          messages: [...state.messages, userMessage, loadingMessage],
          sending: true,
          currentSessionId: originSessionId,
          clearErrorMessage: true,
          suppressSessionRestore: false,
        );
      }

      try {
        final response = await _orchestrator.send(
          AiChatRequest(
            mode: conversationMode,
            userInput: normalized,
            requestId: sendingOperation.requestId,
            backendPreference: backendPreference,
            allowPrivateContext: allowPrivateContext,
            manualItems: manualItems,
          ),
          history: history,
        );
        if (!_canContinue(generation)) {
          return;
        }
        final assistantMessage = ChatMessage(
          id: loadingMessage.id,
          role: ChatMessageRole.assistant,
          text: response.text,
          createdAt: DateTime.now(),
          status: ChatMessageStatus.completed,
          usedPrivateContext: response.usedPrivateContext,
          contextSummary: response.contextSummary,
          sourceType: response.sourceType,
          backendUsage: response.usage,
        );
        await repository.saveSession(
          session.copyWith(
            title: sessionTitle,
            allowPrivateContext: allowPrivateContext,
            lastModelId: response.usage.actualModel,
            updatedAt: assistantMessage.createdAt,
          ),
        );
        if (!_canContinue(generation)) {
          return;
        }
        await repository.saveMessage(
          ChatStoredMessage(
            id: assistantMessage.id,
            sessionId: originSessionId,
            role: ChatStoredMessageRole.assistant,
            content: assistantMessage.text,
            status: ChatStoredMessageStatus.completed,
            usedPrivateContext: assistantMessage.usedPrivateContext,
            autoRetrievedContextSummary: assistantMessage.contextSummary.isEmpty
                ? null
                : assistantMessage.contextSummary.join('；'),
            manualContextItemIds: manualItems
                .map((item) => item.id)
                .toList(growable: false),
            relatedSourceIds: response.contextItems
                .map((item) => item.id)
                .toList(growable: false),
            backendUsage: response.usage,
            createdAt: assistantMessage.createdAt,
          ),
        );
        if (!_canContinue(generation)) {
          return;
        }
        _ref.invalidate(chatSessionsProvider);
        if (_isOriginSelected(originSessionId, conversationMode)) {
          state = state.copyWith(
            messages: _replaceChatMessageById(
              messages: state.messages,
              targetId: loadingMessage.id,
              replacement: assistantMessage,
            ),
            sending: false,
          );
          _invalidateSelectedChatSession(_ref);
        }
      } catch (error) {
        if (!_canContinue(generation)) {
          return;
        }
        final failedMessage = ChatMessage(
          id: loadingMessage.id,
          role: ChatMessageRole.system,
          text: _safeChatErrorMessage(error, backendPreference),
          createdAt: DateTime.now(),
          status: ChatMessageStatus.error,
        );
        await repository.saveSession(
          session.copyWith(
            title: sessionTitle,
            allowPrivateContext: allowPrivateContext,
            updatedAt: failedMessage.createdAt,
          ),
        );
        if (!_canContinue(generation)) {
          return;
        }
        await repository.saveMessage(
          ChatStoredMessage(
            id: failedMessage.id,
            sessionId: originSessionId,
            role: ChatStoredMessageRole.system,
            content: failedMessage.text,
            status: ChatStoredMessageStatus.failed,
            createdAt: failedMessage.createdAt,
          ),
        );
        if (!_canContinue(generation)) {
          return;
        }
        _ref.invalidate(chatSessionsProvider);
        if (_isOriginSelected(originSessionId, conversationMode)) {
          state = state.copyWith(
            messages: _replaceChatMessageById(
              messages: state.messages,
              targetId: loadingMessage.id,
              replacement: failedMessage,
            ),
            sending: false,
            errorMessage: failedMessage.text,
          );
          _invalidateSelectedChatSession(_ref);
        }
      }
    } finally {
      if (identical(_sendingOperations[originSessionId], sendingOperation)) {
        _sendingOperations.remove(originSessionId);
        if (_canContinue(generation) &&
            _isOriginSelected(originSessionId, conversationMode) &&
            state.sending) {
          state = state.copyWith(sending: false);
        }
      }
    }
  }

  void setAllowPrivateContext(bool value) {
    if (!_ref.read(sensitiveStateAccessAllowedProvider)) {
      return;
    }
    state = state.copyWith(allowPrivateContext: value);
  }

  void setBackendPreference(ChatBackendPreference value) {
    if (!_ref.read(sensitiveStateAccessAllowedProvider)) {
      return;
    }
    state = state.copyWith(backendPreference: value);
  }

  void setManualItems(List<ChatContextItem> items) {
    if (!_ref.read(sensitiveStateAccessAllowedProvider)) {
      return;
    }
    state = state.copyWith(manualItems: items);
  }

  void _publishNewOriginSession(String sessionId) {
    _claimSelectionIntent(sessionId);
    _ref.read(suppressRestoredChatSessionProvider.notifier).state = false;
    _ref.read(currentChatSessionIdProvider.notifier).state = sessionId;
    state = state.copyWith(
      currentSessionId: sessionId,
      clearErrorMessage: true,
      suppressSessionRestore: false,
    );
    _invalidateSelectedChatSession(_ref);
  }

  bool _canPublishNewOrigin(
    ChatSessionSelectionIntent startingIntent,
    String? startingSessionId,
    int startingAttempt,
  ) {
    return state.currentSessionId == null &&
        _intentIsCurrent(startingIntent) &&
        _selectionAttemptIsCurrent(startingAttempt) &&
        !_hasPendingSelectionAttempt &&
        _ref.read(currentChatSessionIdProvider) == startingSessionId;
  }

  void _activateExistingOriginSession(String sessionId) {
    _claimSelectionIntent(sessionId);
    _ref.read(suppressRestoredChatSessionProvider.notifier).state = false;
    _ref.read(currentChatSessionIdProvider.notifier).state = sessionId;
    _invalidateSelectedChatSession(_ref);
  }

  Future<void> _cancelActiveRequests() async {
    final operations = _sendingOperations.values.toList(growable: false);
    for (final operation in operations) {
      await _orchestrator.cancel(operation.requestId);
    }
  }
}
