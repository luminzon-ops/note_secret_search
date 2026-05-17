import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/sqlite_chat_session_repository.dart';

final chatSessionRepositoryProvider = Provider<ChatSessionRepository>((ref) {
  return SqliteChatSessionRepository(database: ref.watch(appDatabaseProvider));
});

final chatSessionsProvider = FutureProvider<List<ChatSession>>((ref) async {
  final repository = ref.watch(chatSessionRepositoryProvider);
  return repository.listSessions();
});

final restoredChatSessionIdProvider = FutureProvider<String?>((ref) async {
  final sessions = await ref.watch(chatSessionsProvider.future);
  if (sessions.isEmpty) {
    return null;
  }
  return sessions.first.id;
});

final currentChatSessionIdProvider = StateProvider<String?>((ref) => null);

final suppressRestoredChatSessionProvider = StateProvider<bool>((ref) => false);

final currentChatSessionProvider = FutureProvider<ChatSession?>((ref) async {
  final sessionId = ref.watch(currentChatSessionIdProvider);
  if (sessionId == null || sessionId.isEmpty) {
    if (ref.watch(suppressRestoredChatSessionProvider)) {
      return null;
    }
    final restoredId = await ref.watch(restoredChatSessionIdProvider.future);
    if (restoredId == null || restoredId.isEmpty) {
      return null;
    }
    return ref.watch(chatSessionRepositoryProvider).getSession(restoredId);
  }

  return ref.watch(chatSessionRepositoryProvider).getSession(sessionId);
});

final currentChatMessagesProvider = FutureProvider<List<ChatStoredMessage>>((ref) async {
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

  final repository = ref.watch(chatSessionRepositoryProvider);
  return repository.listMessages(sessionId);
});

final chatSessionControllerProvider = Provider<ChatSessionController>((ref) {
  return ChatSessionController(ref: ref);
});

class ChatSessionController {
  ChatSessionController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> selectSession(String? sessionId) async {
    _ref.read(suppressRestoredChatSessionProvider.notifier).state = false;
    _ref.read(currentChatSessionIdProvider.notifier).state = sessionId;
    _ref.invalidate(currentChatSessionProvider);
    _ref.invalidate(currentChatMessagesProvider);
  }

  Future<void> refreshSessions() async {
    _ref.invalidate(chatSessionsProvider);
    _ref.invalidate(restoredChatSessionIdProvider);
    _ref.invalidate(currentChatSessionProvider);
    _ref.invalidate(currentChatMessagesProvider);
  }
}
