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
}
