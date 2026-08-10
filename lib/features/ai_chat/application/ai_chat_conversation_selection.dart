part of 'ai_chat_providers.dart';

mixin _AiChatConversationSelection on StateNotifier<AiChatConversationState> {
  ChatSessionCoordinator get _sessionCoordinator;
  bool Function() get _sensitiveAccessAllowed;
  int get _generation;

  int _claimSelectionAttempt() {
    return _sessionCoordinator.claimSelectionAttempt();
  }

  bool _selectionAttemptIsCurrent(int expected) {
    return _sessionCoordinator.selectionAttemptIsCurrent(expected);
  }

  bool get _hasPendingSelectionAttempt =>
      _sessionCoordinator.hasPendingSelectionAttempt;

  void _completeSelectionAttempt(int expected) {
    _sessionCoordinator.completeSelectionAttempt(expected);
  }

  ChatSessionSelectionIntent _claimSelectionIntent(String? sessionId) {
    return _sessionCoordinator.claimSelectionIntent(
      sessionId,
      mode: state.mode,
    );
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
    return _sessionCoordinator.intentIsCurrent(expected);
  }

  bool _intentAllowsTarget(
    ChatSessionSelectionIntent intent,
    String sessionId,
  ) {
    return _sessionCoordinator.intentAllowsTarget(
      intent,
      sessionId,
      mode: state.mode,
    );
  }

  bool _isOriginSelected(String sessionId, ChatMode mode) {
    if (state.mode != mode ||
        state.currentSessionId != sessionId ||
        _sessionCoordinator.state.currentSessionId != sessionId) {
      return false;
    }
    final intent = _sessionCoordinator.state.selectionIntent;
    return intent.revision == 0 ||
        (intent.sessionId == sessionId &&
            (intent.mode == null || intent.mode == mode));
  }

  bool _canContinue(int generation) {
    return generation == _generation && _sensitiveAccessAllowed();
  }
}
