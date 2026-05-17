import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';

abstract interface class ChatSessionRepository {
  Future<void> saveSession(ChatSession session);

  Future<void> saveMessage(ChatStoredMessage message);

  Future<List<ChatSession>> listSessions();

  Future<List<ChatStoredMessage>> listMessages(String sessionId);

  Future<ChatSession?> getSession(String sessionId);
}
