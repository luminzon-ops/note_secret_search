part of 'ai_chat_concurrency_test.dart';

void _registerAdditionalChatConcurrencyTests() {
  test(
    'stale send cleanup cannot clear a newer same-session operation',
    () async {
      final llmEngine = _QueuedControllableLlmEngine();
      final repository = _ChatTestRepository(
        sessions: [_session('session-a', ChatMode.freeChat)],
      );
      final container = _buildContainer(
        repository: repository,
        llmEngine: llmEngine,
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.selectSession('session-a');
      final oldSend = controller.send('old send');
      await llmEngine.waitForRequestCount(1);

      container.read(sensitiveStateAccessAllowedProvider.notifier).state =
          false;
      controller.resetForLock();
      container.read(sensitiveStateAccessAllowedProvider.notifier).state = true;
      await controller.selectSession('session-a');

      final newSend = controller.send('new send');
      await llmEngine.waitForRequestCount(2);
      expect(controller.state.sending, isTrue);

      llmEngine.complete(0, 'stale old answer');
      await oldSend;

      await controller.send('third send');

      expect(llmEngine.requestCount, 2);
      expect(controller.state.sending, isTrue);

      llmEngine.complete(1, 'new answer');
      await newSend;

      expect(controller.state.sending, isFalse);
      expect(controller.state.messages.last.text, 'new answer');
    },
  );

  test('missing selection cannot poison an in-flight origin', () async {
    final llmEngine = _ControllableLlmEngine();
    final repository = _ChatTestRepository(
      sessions: [_session('session-a', ChatMode.freeChat)],
      messagesBySession: {
        'session-a': [_message('message-a', 'session-a', 'origin A')],
      },
    );
    final container = _buildContainer(
      repository: repository,
      llmEngine: llmEngine,
    );
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.selectSession('session-a');
    final send = controller.send('answer A');
    await llmEngine.waitForRequest();
    final originIntent = container.read(chatSessionSelectionIntentProvider);
    final intentWrites = <ChatSessionSelectionIntent>[];
    final intentSubscription = container.listen<ChatSessionSelectionIntent>(
      chatSessionSelectionIntentProvider,
      (_, next) => intentWrites.add(next),
    );
    addTearDown(intentSubscription.close);

    await controller.selectSession('missing-session');

    expect(controller.state.currentSessionId, 'session-a');
    expect(controller.state.sending, isTrue);
    expect(container.read(currentChatSessionIdProvider), 'session-a');
    final currentIntent = container.read(chatSessionSelectionIntentProvider);
    expect(currentIntent.revision, originIntent.revision);
    expect(currentIntent.sessionId, originIntent.sessionId);
    expect(currentIntent.mode, originIntent.mode);
    expect(intentWrites, isEmpty);

    llmEngine.complete('completed A');
    await send;

    expect(controller.state.currentSessionId, 'session-a');
    expect(controller.state.messages.last.text, 'completed A');
    expect(controller.state.sending, isFalse);
  });

  test('wrong-mode selection cannot poison an in-flight origin', () async {
    final llmEngine = _ControllableLlmEngine();
    final repository = _ChatTestRepository(
      sessions: [
        _session('session-a', ChatMode.freeChat),
        _session('private-b', ChatMode.privateQa),
      ],
      messagesBySession: {
        'session-a': [_message('message-a', 'session-a', 'origin A')],
      },
    );
    final container = _buildContainer(
      repository: repository,
      llmEngine: llmEngine,
    );
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.selectSession('session-a');
    final send = controller.send('answer A');
    await llmEngine.waitForRequest();
    final originIntent = container.read(chatSessionSelectionIntentProvider);
    final intentWrites = <ChatSessionSelectionIntent>[];
    final intentSubscription = container.listen<ChatSessionSelectionIntent>(
      chatSessionSelectionIntentProvider,
      (_, next) => intentWrites.add(next),
    );
    addTearDown(intentSubscription.close);

    await controller.selectSession('private-b');

    expect(controller.state.currentSessionId, 'session-a');
    expect(controller.state.sending, isTrue);
    expect(container.read(currentChatSessionIdProvider), 'session-a');
    final currentIntent = container.read(chatSessionSelectionIntentProvider);
    expect(currentIntent.revision, originIntent.revision);
    expect(currentIntent.sessionId, originIntent.sessionId);
    expect(currentIntent.mode, originIntent.mode);
    expect(intentWrites, isEmpty);

    llmEngine.complete('completed A');
    await send;

    expect(controller.state.currentSessionId, 'session-a');
    expect(controller.state.messages.last.text, 'completed A');
    expect(controller.state.sending, isFalse);
  });

  test(
    'latest select call wins when an older session validation finishes last',
    () async {
      final repository = _ChatTestRepository(
        sessions: [
          _session('session-a', ChatMode.freeChat),
          _session('session-b', ChatMode.freeChat),
        ],
        messagesBySession: {
          'session-a': [_message('message-a', 'session-a', 'selected A')],
          'session-b': [_message('message-b', 'session-b', 'selected B')],
        },
        blockedSessionGetIds: const {'session-a'},
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      final startingIntent = container.read(chatSessionSelectionIntentProvider);
      final intentWrites = <ChatSessionSelectionIntent>[];
      final intentSubscription = container.listen<ChatSessionSelectionIntent>(
        chatSessionSelectionIntentProvider,
        (_, next) => intentWrites.add(next),
      );
      addTearDown(intentSubscription.close);
      final selectA = controller.selectSession('session-a');
      await repository.waitForSessionGet('session-a');
      final intentDuringA = container.read(chatSessionSelectionIntentProvider);
      expect(intentDuringA.revision, startingIntent.revision);
      expect(intentDuringA.sessionId, startingIntent.sessionId);
      expect(intentDuringA.mode, startingIntent.mode);
      expect(intentWrites, isEmpty);

      await controller.selectSession('session-b');
      final intentAfterB = container.read(chatSessionSelectionIntentProvider);

      repository.completeSessionGet('session-a');
      await selectA;

      _expectSelected(controller, sessionId: 'session-b', text: 'selected B');
      expect(container.read(currentChatSessionIdProvider), 'session-b');
      final finalIntent = container.read(chatSessionSelectionIntentProvider);
      expect(finalIntent.revision, intentAfterB.revision);
      expect(finalIntent.sessionId, intentAfterB.sessionId);
      expect(finalIntent.mode, intentAfterB.mode);
      expect(intentWrites, hasLength(1));
      expect(intentWrites.single.sessionId, 'session-b');
      expect(intentWrites.single.mode, ChatMode.freeChat);
    },
  );

  test(
    'latest cross-controller validation wins through shared intent',
    () async {
      final repository = _ChatTestRepository(
        sessions: [
          _session('session-a', ChatMode.freeChat),
          _session('session-b', ChatMode.privateQa),
        ],
        messagesBySession: {
          'session-a': [_message('message-a', 'session-a', 'free A')],
          'session-b': [_message('message-b', 'session-b', 'private B')],
        },
        blockedSessionGetIds: const {'session-a'},
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final freeController = container.read(
        freeChatControllerProvider.notifier,
      );
      final privateController = container.read(
        privateQaChatControllerProvider.notifier,
      );
      final startingIntent = container.read(chatSessionSelectionIntentProvider);
      final intentWrites = <ChatSessionSelectionIntent>[];
      final intentSubscription = container.listen<ChatSessionSelectionIntent>(
        chatSessionSelectionIntentProvider,
        (_, next) => intentWrites.add(next),
      );
      addTearDown(intentSubscription.close);
      final selectA = freeController.selectSession('session-a');
      await repository.waitForSessionGet('session-a');
      final intentDuringA = container.read(chatSessionSelectionIntentProvider);
      expect(intentDuringA.revision, startingIntent.revision);
      expect(intentDuringA.sessionId, startingIntent.sessionId);
      expect(intentDuringA.mode, startingIntent.mode);
      expect(intentWrites, isEmpty);

      await privateController.selectSession('session-b');
      repository.completeSessionGet('session-a');
      await selectA;

      expect(freeController.state.currentSessionId, isNull);
      _expectSelected(
        privateController,
        sessionId: 'session-b',
        text: 'private B',
      );
      expect(container.read(currentChatSessionIdProvider), 'session-b');
      final finalIntent = container.read(chatSessionSelectionIntentProvider);
      expect(finalIntent.sessionId, 'session-b');
      expect(finalIntent.mode, ChatMode.privateQa);
      expect(intentWrites, hasLength(1));
      expect(intentWrites.single.sessionId, 'session-b');
      expect(intentWrites.single.mode, ChatMode.privateQa);
    },
  );

  test(
    'later cross-controller call wins even when its validation finishes last',
    () async {
      final repository = _ChatTestRepository(
        sessions: [
          _session('session-a', ChatMode.freeChat),
          _session('session-b', ChatMode.privateQa),
        ],
        messagesBySession: {
          'session-a': [_message('message-a', 'session-a', 'free A')],
          'session-b': [_message('message-b', 'session-b', 'private B')],
        },
        blockedSessionGetIds: const {'session-a', 'session-b'},
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final freeController = container.read(
        freeChatControllerProvider.notifier,
      );
      final privateController = container.read(
        privateQaChatControllerProvider.notifier,
      );
      final selectA = freeController.selectSession('session-a');
      await repository.waitForSessionGet('session-a');
      final selectB = privateController.selectSession('session-b');
      await repository.waitForSessionGet('session-b');

      repository.completeSessionGet('session-a');
      await selectA;
      repository.completeSessionGet('session-b');
      await selectB;

      expect(freeController.state.currentSessionId, isNull);
      _expectSelected(
        privateController,
        sessionId: 'session-b',
        text: 'private B',
      );
      expect(container.read(currentChatSessionIdProvider), 'session-b');
      final intent = container.read(chatSessionSelectionIntentProvider);
      expect(intent.sessionId, 'session-b');
      expect(intent.mode, ChatMode.privateQa);
    },
  );

  test('stale rejected selection cannot revive its previous intent', () async {
    final repository = _ChatTestRepository(
      sessions: [
        _session('session-a', ChatMode.freeChat),
        _session('session-b', ChatMode.freeChat),
      ],
      messagesBySession: {
        'session-a': [_message('message-a', 'session-a', 'origin A')],
        'session-b': [_message('message-b', 'session-b', 'selected B')],
      },
      blockedSessionGetIds: const {'missing-session'},
    );
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    await controller.selectSession('session-a');
    final originIntent = container.read(chatSessionSelectionIntentProvider);
    final intentWrites = <ChatSessionSelectionIntent>[];
    final intentSubscription = container.listen<ChatSessionSelectionIntent>(
      chatSessionSelectionIntentProvider,
      (_, next) => intentWrites.add(next),
    );
    addTearDown(intentSubscription.close);

    final rejectedSelection = controller.selectSession('missing-session');
    await repository.waitForSessionGet('missing-session');
    final intentDuringValidation = container.read(
      chatSessionSelectionIntentProvider,
    );
    expect(intentDuringValidation.revision, originIntent.revision);
    expect(intentDuringValidation.sessionId, originIntent.sessionId);
    expect(intentDuringValidation.mode, originIntent.mode);
    expect(intentWrites, isEmpty);

    await controller.selectSession('session-b');
    final intentAfterB = container.read(chatSessionSelectionIntentProvider);
    repository.completeSessionGet('missing-session');
    await rejectedSelection;

    _expectSelected(controller, sessionId: 'session-b', text: 'selected B');
    final finalIntent = container.read(chatSessionSelectionIntentProvider);
    expect(finalIntent.revision, intentAfterB.revision);
    expect(finalIntent.sessionId, intentAfterB.sessionId);
    expect(finalIntent.mode, intentAfterB.mode);
    expect(intentWrites, hasLength(1));
    expect(intentWrites.single.sessionId, 'session-b');
    expect(intentWrites.single.mode, ChatMode.freeChat);
  });

  test(
    'automatic restore is claimed only by the globally newest session mode',
    () async {
      final newerPrivate = _session(
        'private-newer',
        ChatMode.privateQa,
      ).copyWith(updatedAt: DateTime(2026, 7, 15, 10));
      final olderFree = _session(
        'free-older',
        ChatMode.freeChat,
      ).copyWith(updatedAt: DateTime(2026, 7, 15, 9));
      final repository = _ChatTestRepository(
        sessions: [newerPrivate, olderFree],
        messagesBySession: {
          'private-newer': [
            _message('private-message', 'private-newer', 'newest private'),
          ],
          'free-older': [_message('free-message', 'free-older', 'older free')],
        },
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final freeController = container.read(
        freeChatControllerProvider.notifier,
      );
      final privateController = container.read(
        privateQaChatControllerProvider.notifier,
      );

      await freeController.restoreSessionIfNeeded();
      await privateController.restoreSessionIfNeeded();

      expect(freeController.state.currentSessionId, isNull);
      expect(freeController.state.messages, isEmpty);
      _expectSelected(
        privateController,
        sessionId: 'private-newer',
        text: 'newest private',
      );
      expect(container.read(currentChatSessionIdProvider), 'private-newer');
      final intent = container.read(chatSessionSelectionIntentProvider);
      expect(intent.sessionId, 'private-newer');
      expect(intent.mode, ChatMode.privateQa);
    },
  );

  test(
    'concurrent restore completion order still yields the globally newest mode',
    () async {
      final newerPrivate = _session(
        'private-newer',
        ChatMode.privateQa,
      ).copyWith(updatedAt: DateTime(2026, 7, 15, 10));
      final olderFree = _session(
        'free-older',
        ChatMode.freeChat,
      ).copyWith(updatedAt: DateTime(2026, 7, 15, 9));
      final repository = _ChatTestRepository(
        sessions: [newerPrivate, olderFree],
        messagesBySession: {
          'private-newer': [
            _message('private-message', 'private-newer', 'newest private'),
          ],
          'free-older': [_message('free-message', 'free-older', 'older free')],
        },
        blockedMessageSessionIds: const {'private-newer'},
        delaySessionList: true,
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final freeController = container.read(
        freeChatControllerProvider.notifier,
      );
      final privateController = container.read(
        privateQaChatControllerProvider.notifier,
      );

      final freeRestore = freeController.restoreSessionIfNeeded();
      final privateRestore = privateController.restoreSessionIfNeeded();
      await repository.waitForSessionList();

      repository.completeSessionList();
      await repository.waitForMessageList('private-newer');
      await freeRestore;

      expect(freeController.state.currentSessionId, isNull);
      expect(freeController.state.messages, isEmpty);

      repository.completeMessageList('private-newer');
      await privateRestore;

      _expectSelected(
        privateController,
        sessionId: 'private-newer',
        text: 'newest private',
      );
      expect(container.read(currentChatSessionIdProvider), 'private-newer');
      final intent = container.read(chatSessionSelectionIntentProvider);
      expect(intent.sessionId, 'private-newer');
      expect(intent.mode, ChatMode.privateQa);
    },
  );

  test(
    'explicit null intent suppresses automatic restore across controllers',
    () async {
      final repository = _ChatTestRepository(
        sessions: [
          _session('private-newer', ChatMode.privateQa),
          _session('free-older', ChatMode.freeChat),
        ],
        messagesBySession: {
          'private-newer': [
            _message('private-message', 'private-newer', 'newest private'),
          ],
          'free-older': [_message('free-message', 'free-older', 'older free')],
        },
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final freeController = container.read(
        freeChatControllerProvider.notifier,
      );
      final privateController = container.read(
        privateQaChatControllerProvider.notifier,
      );
      await freeController.startNewSession();
      final explicitIntent = container.read(chatSessionSelectionIntentProvider);

      await privateController.restoreSessionIfNeeded();
      await freeController.restoreSessionIfNeeded();

      expect(explicitIntent.revision, greaterThan(0));
      expect(explicitIntent.sessionId, isNull);
      expect(container.read(currentChatSessionIdProvider), isNull);
      expect(freeController.state.currentSessionId, isNull);
      expect(privateController.state.currentSessionId, isNull);
      expect(freeController.state.messages, isEmpty);
      expect(privateController.state.messages, isEmpty);
      final finalIntent = container.read(chatSessionSelectionIntentProvider);
      expect(finalIntent.revision, explicitIntent.revision);
      expect(finalIntent.sessionId, isNull);
    },
  );
}
