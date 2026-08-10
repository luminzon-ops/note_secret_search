part of 'ai_chat_concurrency_test.dart';

void _registerRestoreSelectionRaceTests() {
  test(
    'pending explicit selection prevents automatic restore from winning',
    () async {
      final repository = _ChatTestRepository(
        sessions: [
          _session('session-a', ChatMode.freeChat),
          _session('session-b', ChatMode.freeChat),
        ],
        messagesBySession: {
          'session-a': [_message('message-a', 'session-a', 'restored A')],
          'session-b': [_message('message-b', 'session-b', 'selected B')],
        },
        blockedSessionGetIds: const {'session-b'},
      );
      final container = _buildContainer(repository: repository);
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      final selectB = controller.selectSession('session-b');
      await repository.waitForSessionGet('session-b');

      await controller.restoreSessionIfNeeded();

      expect(controller.state.currentSessionId, isNull);
      expect(container.read(currentChatSessionIdProvider), isNull);

      repository.completeSessionGet('session-b');
      await selectB;

      _expectSelected(controller, sessionId: 'session-b', text: 'selected B');
      expect(container.read(currentChatSessionIdProvider), 'session-b');
    },
  );

  test('pending explicit selection prevents new-session publication', () async {
    final repository = _ChatTestRepository(
      sessions: [_session('session-b', ChatMode.freeChat)],
      messagesBySession: {
        'session-b': [_message('message-b', 'session-b', 'selected B')],
      },
      blockedSessionGetIds: const {'session-b'},
      delaySessionSave: true,
    );
    final container = _buildContainer(repository: repository);
    addTearDown(container.dispose);

    final controller = container.read(freeChatControllerProvider.notifier);
    final send = controller.send('new A');
    final pendingSession = await repository.waitForSessionSave();
    final selectB = controller.selectSession('session-b');
    await repository.waitForSessionGet('session-b');

    repository.completeSessionSave();
    await send;

    expect(controller.state.currentSessionId, isNull);
    expect(container.read(currentChatSessionIdProvider), isNull);

    repository.completeSessionGet('session-b');
    await selectB;

    expect(pendingSession.id, isNot('session-b'));
    _expectSelected(controller, sessionId: 'session-b', text: 'selected B');
    expect(container.read(currentChatSessionIdProvider), 'session-b');
  });
}
