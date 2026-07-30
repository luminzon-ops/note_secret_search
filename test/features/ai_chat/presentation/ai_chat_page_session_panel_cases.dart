part of 'ai_chat_page_test.dart';

void _runAiChatSessionPanelCases() {
  testWidgets(
    'AI chat page lists existing sessions and can switch between them',
    (tester) async {
      final container = await _buildContainer(
        chatRepository: _FakeChatSessionRepository(
          sessions: [
            ChatSession(
              id: 'session-1',
              mode: ChatMode.privateQa,
              title: '邮箱问答',
              allowPrivateContext: true,
              archived: false,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
            ),
            ChatSession(
              id: 'session-2',
              mode: ChatMode.freeChat,
              title: '自由对话',
              allowPrivateContext: false,
              archived: false,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(4000),
            ),
          ],
          messagesBySession: {
            'session-1': [
              ChatStoredMessage(
                id: 'm1',
                sessionId: 'session-1',
                role: ChatStoredMessageRole.user,
                content: '邮箱历史',
                status: ChatStoredMessageStatus.completed,
                createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
              ),
            ],
            'session-2': [
              ChatStoredMessage(
                id: 'm2',
                sessionId: 'session-2',
                role: ChatStoredMessageRole.user,
                content: '自由聊天历史',
                status: ChatStoredMessageStatus.completed,
                createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
              ),
            ],
          },
        ),
      );

      final router = container.read(appRouterProvider);
      router.go('/ai/chat');

      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('最近会话'), findsOneWidget);
      expect(find.text('邮箱问答'), findsOneWidget);
      expect(find.text('自由对话'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, '自由对话'));
      await tester.pumpAndSettle();

      expect(container.read(currentChatSessionIdProvider), 'session-2');
    },
  );

  testWidgets('AI chat page exposes new session entry in session panel', (
    tester,
  ) async {
    final container = await _buildContainer(
      chatRepository: _FakeChatSessionRepository(
        sessions: [
          ChatSession(
            id: 'session-1',
            mode: ChatMode.freeChat,
            title: '自由对话',
            allowPrivateContext: false,
            archived: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
        ],
      ),
    );

    final router = container.read(appRouterProvider);
    router.go('/ai/chat');

    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await container
        .read(chatSessionCoordinatorProvider.notifier)
        .selectSharedSession('session-1');
    await tester.pumpAndSettle();

    expect(container.read(currentChatSessionIdProvider), 'session-1');
    expect(find.text('新建会话'), findsOneWidget);

    await tester.tap(find.text('新建会话'));
    await tester.pumpAndSettle();

    expect(container.read(currentChatSessionIdProvider), isNull);
    expect(await container.read(currentChatSessionProvider.future), isNull);
  });

  testWidgets(
    'AI chat page can reopen an old session after starting a new session',
    (tester) async {
      final container = await _buildContainer(
        chatRepository: _FakeChatSessionRepository(
          sessions: [
            ChatSession(
              id: 'session-1',
              mode: ChatMode.freeChat,
              title: '自由对话',
              allowPrivateContext: false,
              archived: false,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(5000),
            ),
          ],
          messagesBySession: {
            'session-1': [
              ChatStoredMessage(
                id: 'm1',
                sessionId: 'session-1',
                role: ChatStoredMessageRole.user,
                content: '旧会话消息',
                status: ChatStoredMessageStatus.completed,
                createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
              ),
            ],
          },
        ),
      );

      final router = container.read(appRouterProvider);
      router.go('/ai/chat');

      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('自由聊天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建会话'));
      await tester.pumpAndSettle();

      expect(container.read(freeChatControllerProvider).messages, isEmpty);

      await tester.tap(find.text('自由对话'));
      await tester.pumpAndSettle();

      expect(container.read(currentChatSessionIdProvider), 'session-1');
      expect(
        container.read(freeChatControllerProvider).currentSessionId,
        'session-1',
      );
      expect(
        container.read(freeChatControllerProvider).messages.single.text,
        '旧会话消息',
      );
      expect(find.text('旧会话消息'), findsOneWidget);
    },
  );
}
