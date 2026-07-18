import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/sqlite_chat_session_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test('updating a chat session preserves its messages', () async {
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
        updatedAt: DateTime.fromMillisecondsSinceEpoch(3),
      ),
    );

    expect(await repository.listMessages(session.id), hasLength(1));
  });
}
