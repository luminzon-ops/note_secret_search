import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_backend_usage.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/sqlite_chat_session_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test(
    'updating a chat session preserves creation time and messages',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      final repository = SqliteChatSessionRepository(database: database);
      final session = ChatSession(
        id: 'session-1',
        mode: ChatMode.freeChat,
        title: 'Original',
        allowPrivateContext: false,
        archived: false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      );
      await repository.saveSession(session);
      await repository.saveMessage(
        ChatStoredMessage(
          id: 'message-1',
          sessionId: session.id,
          role: ChatStoredMessageRole.user,
          content: 'Preserved',
          status: ChatStoredMessageStatus.completed,
          createdAt: DateTime.fromMillisecondsSinceEpoch(2),
        ),
      );

      await repository.saveSession(
        session.copyWith(
          title: 'Updated',
          createdAt: DateTime.fromMillisecondsSinceEpoch(99),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(3),
        ),
      );

      final restored = await repository.getSession(session.id);
      expect(restored?.title, 'Updated');
      expect(restored?.createdAt, session.createdAt);
      expect(restored?.updatedAt, DateTime.fromMillisecondsSinceEpoch(3));
      expect(await repository.listMessages(session.id), hasLength(1));
    },
  );

  test(
    'round trips actual backend provenance while preserving legacy nulls',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      final repository = SqliteChatSessionRepository(database: database);
      final session = ChatSession(
        id: 'session-usage',
        mode: ChatMode.freeChat,
        title: 'Usage',
        allowPrivateContext: false,
        archived: false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(10),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(10),
      );
      await repository.saveSession(session);
      await repository.saveMessage(
        ChatStoredMessage(
          id: 'legacy-message',
          sessionId: session.id,
          role: ChatStoredMessageRole.user,
          content: 'legacy',
          status: ChatStoredMessageStatus.completed,
          createdAt: DateTime.fromMillisecondsSinceEpoch(11),
        ),
      );
      await repository.saveMessage(
        ChatStoredMessage(
          id: 'actual-message',
          sessionId: session.id,
          role: ChatStoredMessageRole.assistant,
          content: 'local answer',
          status: ChatStoredMessageStatus.completed,
          backendUsage: const ChatBackendUsage(
            actualBackend: 'local_llama_cpp',
            actualModel: 'model-1',
            providerFingerprint: 'fingerprint-1',
          ),
          createdAt: DateTime.fromMillisecondsSinceEpoch(12),
        ),
      );

      final messages = await repository.listMessages(session.id);
      final legacy = messages.firstWhere(
        (message) => message.id == 'legacy-message',
      );
      final actual = messages.firstWhere(
        (message) => message.id == 'actual-message',
      );
      expect(legacy.backendUsage, isNull);
      expect(actual.backendUsage?.actualBackend, 'local_llama_cpp');
      expect(actual.backendUsage?.actualModel, 'model-1');
      expect(actual.backendUsage?.providerFingerprint, 'fingerprint-1');
    },
  );
}
