part of 'ai_chat_providers_test.dart';

void _runAiChatHistoryCases() {
  test(
    'controller sends only complete prior turns and preserves session creation time',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _FakeLlmEngine();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.send('FIRST_USER_TURN');
      final originalCreatedAt = fakeRepository.savedSessions.single.createdAt;

      await controller.send('SECOND_USER_TURN');

      expect(fakeLlmEngine.requests, hasLength(2));
      expect(fakeLlmEngine.requests.last.prompt, contains('FIRST_USER_TURN'));
      expect(fakeLlmEngine.requests.last.prompt, contains('普通回答'));
      expect(fakeLlmEngine.requests.last.prompt, contains('SECOND_USER_TURN'));
      expect(fakeRepository.savedSessions.single.createdAt, originalCreatedAt);
    },
  );

  test(
    'controller excludes failed and incomplete turns from history',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _FailThenSucceedLlmEngine();
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          localLlmReadinessProvider.overrideWith(
            (ref) async => const LocalLlmReadiness(
              ready: true,
              reason: 'ready',
              activeModel: _llmModel,
              runtimeState: LlmRuntimeState(
                ready: true,
                reason: 'ready',
                status: LlmRuntimeStatus.ready,
              ),
            ),
          ),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
          llmEngineProvider.overrideWithValue(fakeLlmEngine),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.send('FAILED_USER_TURN');
      await controller.send('RECOVERY_USER_TURN');

      expect(fakeLlmEngine.requests, hasLength(2));
      expect(
        fakeLlmEngine.requests.last.prompt,
        isNot(contains('FAILED_USER_TURN')),
      );
      expect(fakeLlmEngine.requests.last.prompt, isNot(contains('本地模型请求失败')));
      expect(
        fakeLlmEngine.requests.last.prompt,
        contains('RECOVERY_USER_TURN'),
      );
    },
  );

  test(
    'controller starts a blank new session without restoring the latest old session',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final previousSession = ChatSession(
        id: 'session-old',
        mode: ChatMode.freeChat,
        title: '旧会话',
        allowPrivateContext: false,
        archived: false,
        createdAt: DateTime(2026, 5, 11, 19),
        updatedAt: DateTime(2026, 5, 11, 19, 10),
      );
      await fakeRepository.saveSession(previousSession);
      await fakeRepository.saveMessage(
        ChatStoredMessage(
          id: 'message-old',
          sessionId: previousSession.id,
          role: ChatStoredMessageRole.user,
          content: '旧消息',
          status: ChatStoredMessageStatus.completed,
          createdAt: previousSession.updatedAt,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.restoreSessionIfNeeded();
      expect(controller.state.currentSessionId, previousSession.id);
      expect(controller.state.messages.single.text, '旧消息');

      await controller.startNewSession();
      await controller.restoreSessionIfNeeded();

      expect(controller.state.currentSessionId, isNull);
      expect(controller.state.messages, isEmpty);
      expect(container.read(currentChatSessionIdProvider), isNull);
    },
  );

  test(
    'shared session providers stay blank after explicit new session',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final previousSession = ChatSession(
        id: 'session-old',
        mode: ChatMode.freeChat,
        title: '旧会话',
        allowPrivateContext: false,
        archived: false,
        createdAt: DateTime(2026, 5, 11, 20),
        updatedAt: DateTime(2026, 5, 11, 20, 10),
      );
      await fakeRepository.saveSession(previousSession);
      await fakeRepository.saveMessage(
        ChatStoredMessage(
          id: 'message-old',
          sessionId: previousSession.id,
          role: ChatStoredMessageRole.user,
          content: '旧消息',
          status: ChatStoredMessageStatus.completed,
          createdAt: previousSession.updatedAt,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          chatSessionRepositoryProvider.overrideWithValue(fakeRepository),
        ],
      );

      addTearDown(container.dispose);

      final controller = container.read(freeChatControllerProvider.notifier);
      await controller.startNewSession();

      final currentSession = await container.read(
        currentChatSessionProvider.future,
      );
      final currentMessages = await container.read(
        currentChatMessagesProvider.future,
      );

      expect(currentSession, isNull);
      expect(currentMessages, isEmpty);
    },
  );
}
