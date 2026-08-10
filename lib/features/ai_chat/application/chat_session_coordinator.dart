import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';

typedef ChatSessionInvalidator = void Function();

class ChatSessionSelectionIntent {
  const ChatSessionSelectionIntent({
    required this.revision,
    this.sessionId,
    this.mode,
  });

  final int revision;
  final String? sessionId;
  final ChatMode? mode;
}

class ChatSessionCoordinationState {
  const ChatSessionCoordinationState({
    this.currentSessionId,
    this.suppressRestore = false,
    this.selectionIntent = const ChatSessionSelectionIntent(revision: 0),
    this.selectionAttempt = 0,
    this.pendingSelectionAttempt,
  });

  final String? currentSessionId;
  final bool suppressRestore;
  final ChatSessionSelectionIntent selectionIntent;
  final int selectionAttempt;
  final int? pendingSelectionAttempt;
}

class ChatSessionCoordinator
    extends StateNotifier<ChatSessionCoordinationState> {
  ChatSessionCoordinator({required ChatSessionInvalidator invalidateSessions})
    : _invalidateSessions = invalidateSessions,
      super(const ChatSessionCoordinationState());

  final ChatSessionInvalidator _invalidateSessions;

  int claimSelectionAttempt() {
    final next = state.selectionAttempt + 1;
    _setState(
      selectionAttempt: next,
      pendingSelectionAttempt: next,
      replacePendingSelectionAttempt: true,
    );
    return next;
  }

  bool selectionAttemptIsCurrent(int expected) {
    return state.selectionAttempt == expected;
  }

  bool get hasPendingSelectionAttempt => state.pendingSelectionAttempt != null;

  void completeSelectionAttempt(int expected) {
    if (state.pendingSelectionAttempt == expected) {
      _setState(
        pendingSelectionAttempt: null,
        replacePendingSelectionAttempt: true,
      );
    }
  }

  void cancelPendingSelectionAttempts() {
    _setState(
      selectionAttempt: state.selectionAttempt + 1,
      pendingSelectionAttempt: null,
      replacePendingSelectionAttempt: true,
    );
  }

  ChatSessionSelectionIntent claimSelectionIntent(
    String? sessionId, {
    ChatMode? mode,
  }) {
    final next = ChatSessionSelectionIntent(
      revision: state.selectionIntent.revision + 1,
      sessionId: sessionId,
      mode: mode,
    );
    _setState(selectionIntent: next);
    return next;
  }

  bool intentIsCurrent(ChatSessionSelectionIntent expected) {
    final current = state.selectionIntent;
    return current.revision == expected.revision &&
        current.sessionId == expected.sessionId &&
        current.mode == expected.mode;
  }

  bool intentAllowsTarget(
    ChatSessionSelectionIntent intent,
    String sessionId, {
    required ChatMode mode,
  }) {
    if (intent.revision == 0) {
      return true;
    }
    return intent.sessionId == sessionId &&
        (intent.mode == null || intent.mode == mode);
  }

  void publishSession(String? sessionId, {required bool suppressRestore}) {
    _setState(
      currentSessionId: sessionId,
      replaceCurrentSessionId: true,
      suppressRestore: suppressRestore,
    );
  }

  Future<void> selectSharedSession(String? sessionId) async {
    cancelPendingSelectionAttempts();
    claimSelectionIntent(sessionId);
    publishSession(sessionId, suppressRestore: false);
  }

  void resetForNewSession({required ChatMode mode}) {
    cancelPendingSelectionAttempts();
    claimSelectionIntent(null, mode: mode);
    publishSession(null, suppressRestore: true);
  }

  void resetForLock() {
    cancelPendingSelectionAttempts();
    claimSelectionIntent(null);
    publishSession(null, suppressRestore: true);
  }

  void refreshSessions() {
    _invalidateSessions();
  }

  void _setState({
    String? currentSessionId,
    bool replaceCurrentSessionId = false,
    bool? suppressRestore,
    ChatSessionSelectionIntent? selectionIntent,
    int? selectionAttempt,
    int? pendingSelectionAttempt,
    bool replacePendingSelectionAttempt = false,
  }) {
    state = ChatSessionCoordinationState(
      currentSessionId: replaceCurrentSessionId
          ? currentSessionId
          : state.currentSessionId,
      suppressRestore: suppressRestore ?? state.suppressRestore,
      selectionIntent: selectionIntent ?? state.selectionIntent,
      selectionAttempt: selectionAttempt ?? state.selectionAttempt,
      pendingSelectionAttempt: replacePendingSelectionAttempt
          ? pendingSelectionAttempt
          : state.pendingSelectionAttempt,
    );
  }
}
