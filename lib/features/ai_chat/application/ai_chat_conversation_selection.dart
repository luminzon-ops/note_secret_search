part of 'ai_chat_providers.dart';

mixin _AiChatConversationSelection on StateNotifier<AiChatConversationState> {
  Ref get _ref;
  int get _generation;

  int _claimSelectionAttempt() {
    final current = _ref.read(chatSessionSelectionAttemptProvider);
    final next = current + 1;
    _ref.read(chatSessionSelectionAttemptProvider.notifier).state = next;
    return next;
  }

  bool _selectionAttemptIsCurrent(int expected) {
    return _ref.read(chatSessionSelectionAttemptProvider) == expected;
  }

  ChatSessionSelectionIntent _claimSelectionIntent(String? sessionId) {
    final current = _ref.read(chatSessionSelectionIntentProvider);
    final next = ChatSessionSelectionIntent(
      revision: current.revision + 1,
      sessionId: sessionId,
      mode: state.mode,
    );
    _ref.read(chatSessionSelectionIntentProvider.notifier).state = next;
    return next;
  }

  bool _restoreCanContinue(int generation, ChatSessionSelectionIntent intent) {
    return _canContinue(generation) && _intentIsCurrent(intent);
  }

  bool _selectionCanContinue(
    int generation,
    ChatSessionSelectionIntent intent,
    String sessionId,
  ) {
    return _restoreCanContinue(generation, intent) &&
        _intentAllowsTarget(intent, sessionId);
  }

  bool _intentIsCurrent(ChatSessionSelectionIntent expected) {
    final current = _ref.read(chatSessionSelectionIntentProvider);
    return current.revision == expected.revision &&
        current.sessionId == expected.sessionId &&
        current.mode == expected.mode;
  }

  bool _intentAllowsTarget(
    ChatSessionSelectionIntent intent,
    String sessionId,
  ) {
    if (intent.revision == 0) {
      return true;
    }
    return intent.sessionId == sessionId &&
        (intent.mode == null || intent.mode == state.mode);
  }

  bool _isOriginSelected(String sessionId, ChatMode mode) {
    if (state.mode != mode ||
        state.currentSessionId != sessionId ||
        _ref.read(currentChatSessionIdProvider) != sessionId) {
      return false;
    }
    final intent = _ref.read(chatSessionSelectionIntentProvider);
    return intent.revision == 0 ||
        (intent.sessionId == sessionId &&
            (intent.mode == null || intent.mode == mode));
  }

  bool _canContinue(int generation) {
    return generation == _generation &&
        _ref.read(sensitiveStateAccessAllowedProvider);
  }
}
