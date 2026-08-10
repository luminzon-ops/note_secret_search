import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_coordinator.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';

export 'package:note_secret_search/features/ai_chat/application/chat_session_coordinator.dart';

final chatSessionRepositoryProvider = Provider<ChatSessionRepository>((ref) {
  throw StateError(
    'chatSessionRepositoryProvider must be overridden by app composition',
  );
});

final chatSessionsProvider = FutureProvider<List<ChatSession>>((ref) {
  return guardSensitiveFuture<List<ChatSession>>(
    ref,
    lockedValue: const <ChatSession>[],
    load: () => ref.watch(chatSessionRepositoryProvider).listSessions(),
  );
});

final restoredChatSessionIdProvider = FutureProvider<String?>((ref) {
  return guardSensitiveFuture<String?>(
    ref,
    lockedValue: null,
    load: () async {
      final sessions = await ref.watch(chatSessionsProvider.future);
      if (sessions.isEmpty) {
        return null;
      }
      return sessions.first.id;
    },
  );
});

final StateNotifierProvider<
  ChatSessionCoordinator,
  ChatSessionCoordinationState
>
chatSessionCoordinatorProvider =
    StateNotifierProvider<ChatSessionCoordinator, ChatSessionCoordinationState>(
      (ref) {
        return ChatSessionCoordinator(
          invalidateSessions: () {
            ref.invalidate(chatSessionsProvider);
            ref.invalidate(restoredChatSessionIdProvider);
          },
        );
      },
    );

final Provider<String?> currentChatSessionIdProvider = Provider<String?>((ref) {
  return ref.watch(
    chatSessionCoordinatorProvider.select((state) => state.currentSessionId),
  );
});

final Provider<bool> suppressRestoredChatSessionProvider = Provider<bool>((
  ref,
) {
  return ref.watch(
    chatSessionCoordinatorProvider.select((state) => state.suppressRestore),
  );
});

final Provider<ChatSessionSelectionIntent> chatSessionSelectionIntentProvider =
    Provider<ChatSessionSelectionIntent>((ref) {
      return ref.watch(
        chatSessionCoordinatorProvider.select((state) => state.selectionIntent),
      );
    });

final Provider<int> chatSessionSelectionAttemptProvider = Provider<int>((ref) {
  return ref.watch(
    chatSessionCoordinatorProvider.select((state) => state.selectionAttempt),
  );
});

final Provider<int?> chatSessionSelectionPendingAttemptProvider =
    Provider<int?>((ref) {
      return ref.watch(
        chatSessionCoordinatorProvider.select(
          (state) => state.pendingSelectionAttempt,
        ),
      );
    });

final FutureProvider<ChatSession?> currentChatSessionProvider =
    FutureProvider<ChatSession?>((ref) {
      return guardSensitiveFuture<ChatSession?>(
        ref,
        lockedValue: null,
        load: () async {
          final sessionId = ref.watch(currentChatSessionIdProvider);
          if (sessionId == null || sessionId.isEmpty) {
            if (ref.watch(suppressRestoredChatSessionProvider)) {
              return null;
            }
            final restoredId = await ref.watch(
              restoredChatSessionIdProvider.future,
            );
            if (restoredId == null || restoredId.isEmpty) {
              return null;
            }
            return ref
                .watch(chatSessionRepositoryProvider)
                .getSession(restoredId);
          }

          return ref.watch(chatSessionRepositoryProvider).getSession(sessionId);
        },
      );
    });

final FutureProvider<List<ChatStoredMessage>> currentChatMessagesProvider =
    FutureProvider<List<ChatStoredMessage>>((ref) {
      return guardSensitiveFuture<List<ChatStoredMessage>>(
        ref,
        lockedValue: const <ChatStoredMessage>[],
        load: () async {
          var sessionId = ref.watch(currentChatSessionIdProvider);
          if (sessionId == null || sessionId.isEmpty) {
            if (ref.watch(suppressRestoredChatSessionProvider)) {
              return const <ChatStoredMessage>[];
            }
            sessionId = await ref.watch(restoredChatSessionIdProvider.future);
          }

          if (sessionId == null || sessionId.isEmpty) {
            return const <ChatStoredMessage>[];
          }

          return ref
              .watch(chatSessionRepositoryProvider)
              .listMessages(sessionId);
        },
      );
    });
