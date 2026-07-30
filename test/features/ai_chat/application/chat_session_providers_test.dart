import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session_repository.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/sqlite_chat_session_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

part 'chat_session_providers_fakes.dart';

void main() {
  late Database database;
  late _TestAppDatabase appDatabase;
  late SqliteChatSessionRepository repository;

  setUp(() {
    database = _InMemoryDatabase();
    appDatabase = _TestAppDatabase(database);
    repository = SqliteChatSessionRepository(database: appDatabase);
  });

  tearDown(() async {
    await database.close();
  });

  test('creates a chat session and stores messages', () async {
    final session = ChatSession(
      id: 'session-1',
      mode: ChatMode.privateQa,
      title: '邮箱问答',
      allowPrivateContext: true,
      lastModelId: 'llm-1',
      archived: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    final message = ChatStoredMessage(
      id: 'msg-1',
      sessionId: 'session-1',
      role: ChatStoredMessageRole.assistant,
      content: '这是回答',
      status: ChatStoredMessageStatus.completed,
      usedPrivateContext: true,
      autoRetrievedContextSummary: '命中邮箱说明',
      manualContextItemIds: const ['note-1'],
      relatedSourceIds: const ['note-1', 'secret-1'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
    );

    await repository.saveSession(session);
    await repository.saveMessage(message);

    final storedSession = await repository.getSession('session-1');
    final storedMessages = await repository.listMessages('session-1');

    expect(storedSession, isNotNull);
    expect(storedSession?.title, '邮箱问答');
    expect(storedSession?.allowPrivateContext, isTrue);
    expect(storedMessages, hasLength(1));
    expect(storedMessages.first.content, '这是回答');
    expect(storedMessages.first.manualContextItemIds, ['note-1']);
    expect(storedMessages.first.relatedSourceIds, ['note-1', 'secret-1']);
  });

  test('lists sessions ordered by updatedAt desc', () async {
    await repository.saveSession(
      ChatSession(
        id: 'session-older',
        mode: ChatMode.freeChat,
        title: '旧会话',
        allowPrivateContext: false,
        archived: false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    );
    await repository.saveSession(
      ChatSession(
        id: 'session-newer',
        mode: ChatMode.privateQa,
        title: '新会话',
        allowPrivateContext: true,
        archived: false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
      ),
    );

    final sessions = await repository.listSessions();

    expect(sessions.map((item) => item.id).toList(), [
      'session-newer',
      'session-older',
    ]);
  });

  test('loads messages for an existing session', () async {
    await repository.saveSession(
      ChatSession(
        id: 'session-1',
        mode: ChatMode.freeChat,
        title: '自由聊天',
        allowPrivateContext: false,
        archived: false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    );
    await repository.saveMessage(
      ChatStoredMessage(
        id: 'msg-1',
        sessionId: 'session-1',
        role: ChatStoredMessageRole.user,
        content: '你好',
        status: ChatStoredMessageStatus.completed,
        createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
      ),
    );
    await repository.saveMessage(
      ChatStoredMessage(
        id: 'msg-2',
        sessionId: 'session-1',
        role: ChatStoredMessageRole.assistant,
        content: '你好，我在。',
        status: ChatStoredMessageStatus.completed,
        createdAt: DateTime.fromMillisecondsSinceEpoch(4000),
      ),
    );

    final messages = await repository.listMessages('session-1');

    expect(messages, hasLength(2));
    expect(messages.first.id, 'msg-1');
    expect(messages.last.id, 'msg-2');
  });

  test(
    'chatSessionsProvider returns repository sessions ordered by updatedAt desc',
    () async {
      final fakeRepository = _FakeChatSessionRepository(
        sessions: [
          ChatSession(
            id: 'older',
            mode: ChatMode.freeChat,
            title: '旧会话',
            allowPrivateContext: false,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          ),
          ChatSession(
            id: 'newer',
            mode: ChatMode.privateQa,
            title: '新会话',
            allowPrivateContext: true,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );

      addTearDown(container.dispose);

      final sessions = await container.read(chatSessionsProvider.future);
      expect(sessions.map((item) => item.id).toList(), ['newer', 'older']);
    },
  );

  test(
    'currentChatMessagesProvider returns empty when no current session is selected',
    () async {
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          chatSessionRepositoryProvider.overrideWithValue(
            _FakeChatSessionRepository(),
          ),
        ],
      );

      addTearDown(container.dispose);

      final messages = await container.read(currentChatMessagesProvider.future);
      expect(messages, isEmpty);
    },
  );

  test(
    'currentChatMessagesProvider loads messages for selected session',
    () async {
      final fakeRepository = _FakeChatSessionRepository(
        messagesBySession: {
          'session-1': [
            ChatStoredMessage(
              id: 'msg-1',
              sessionId: 'session-1',
              role: ChatStoredMessageRole.user,
              content: '你好',
              status: ChatStoredMessageStatus.completed,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(chatSessionCoordinatorProvider.notifier)
          .selectSharedSession('session-1');

      final messages = await container.read(currentChatMessagesProvider.future);
      expect(messages, hasLength(1));
      expect(messages.first.id, 'msg-1');
    },
  );

  test('restores the most recent chat session on page load', () async {
    final fakeRepository = _FakeChatSessionRepository(
      sessions: [
        ChatSession(
          id: 'older',
          mode: ChatMode.freeChat,
          title: '旧会话',
          allowPrivateContext: false,
          archived: false,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
        ChatSession(
          id: 'newest',
          mode: ChatMode.privateQa,
          title: '最新会话',
          allowPrivateContext: true,
          archived: false,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(9000),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
      ],
    );

    addTearDown(container.dispose);

    final restoredId = await container.read(
      restoredChatSessionIdProvider.future,
    );
    expect(restoredId, 'newest');
  });

  test('switching sessions loads the correct message history', () async {
    final fakeRepository = _FakeChatSessionRepository(
      messagesBySession: {
        'session-a': [
          ChatStoredMessage(
            id: 'a-1',
            sessionId: 'session-a',
            role: ChatStoredMessageRole.user,
            content: '会话A',
            status: ChatStoredMessageStatus.completed,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        ],
        'session-b': [
          ChatStoredMessage(
            id: 'b-1',
            sessionId: 'session-b',
            role: ChatStoredMessageRole.user,
            content: '会话B',
            status: ChatStoredMessageStatus.completed,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        ],
      },
    );
    final container = ProviderContainer(
      overrides: [
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
      ],
    );

    addTearDown(container.dispose);

    await container
        .read(chatSessionCoordinatorProvider.notifier)
        .selectSharedSession('session-a');
    final firstMessages = await container.read(
      currentChatMessagesProvider.future,
    );
    expect(firstMessages.single.id, 'a-1');

    container.invalidate(currentChatMessagesProvider);
    await container
        .read(chatSessionCoordinatorProvider.notifier)
        .selectSharedSession('session-b');
    final secondMessages = await container.read(
      currentChatMessagesProvider.future,
    );
    expect(secondMessages.single.id, 'b-1');
  });
}
