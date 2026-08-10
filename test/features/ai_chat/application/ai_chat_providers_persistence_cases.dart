part of 'ai_chat_providers_test.dart';

void _runAiChatPersistenceCases() {
  test(
    'controller persists user and assistant messages with session metadata after successful send',
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
      await controller.send('你好，继续聊天');

      expect(fakeRepository.savedSessions, hasLength(1));
      expect(fakeRepository.savedMessages, hasLength(2));
      expect(
        fakeRepository.savedMessages.first.role,
        ChatStoredMessageRole.user,
      );
      expect(
        fakeRepository.savedMessages.last.role,
        ChatStoredMessageRole.assistant,
      );
      expect(
        fakeRepository.savedMessages.last.status,
        ChatStoredMessageStatus.completed,
      );
      expect(
        fakeRepository.savedMessages.first.sessionId,
        fakeRepository.savedMessages.last.sessionId,
      );
      expect(fakeRepository.savedSessions.last.lastModelId, 'llm-1');
      expect(
        fakeRepository.savedMessages.last.backendUsage?.actualBackend,
        'llama.cpp',
      );
      expect(
        fakeRepository.savedMessages.last.backendUsage?.actualModel,
        'llm-1',
      );
      expect(
        fakeRepository.savedSessions.single.updatedAt.isAfter(
          fakeRepository.savedSessions.single.createdAt,
        ),
        isTrue,
      );
    },
  );

  test(
    'controller persists failed assistant-side message when generation fails',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _ThrowingLlmEngine();
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
      await controller.send('这次会失败');

      expect(fakeRepository.savedMessages, hasLength(2));
      expect(
        fakeRepository.savedMessages.last.role,
        ChatStoredMessageRole.system,
      );
      expect(
        fakeRepository.savedMessages.last.status,
        ChatStoredMessageStatus.failed,
      );
      expect(fakeRepository.savedSessions.single.lastModelId, isNull);
    },
  );

  test(
    'controller keeps failed assistant message persistence when runtime reports degraded generation',
    () async {
      final fakeRepository = _FakeChatSessionRepository();
      final fakeLlmEngine = _ThrowingLlmEngine(message: '真实本地 LLM 生成失败');
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
      await controller.send('运行真实本地 LLM');

      expect(
        fakeRepository.savedMessages.last.role,
        ChatStoredMessageRole.system,
      );
      expect(
        fakeRepository.savedMessages.last.status,
        ChatStoredMessageStatus.failed,
      );
      expect(fakeRepository.savedMessages.last.content, '本地模型请求失败，请稍后重试。');
      expect(
        fakeRepository.savedMessages.last.content,
        isNot(contains('真实本地 LLM 生成失败')),
      );
    },
  );

  test(
    'controller creates paired user and assistant messages with shared correlation timestamp',
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
      await controller.send('你好，配对测试');

      expect(fakeRepository.savedMessages, hasLength(2));

      final userMessage = fakeRepository.savedMessages.firstWhere(
        (message) => message.role == ChatStoredMessageRole.user,
      );
      final assistantMessage = fakeRepository.savedMessages.firstWhere(
        (message) => message.role == ChatStoredMessageRole.assistant,
      );

      final userMicros = int.parse(userMessage.id.replaceFirst('user-', ''));
      final assistantMicros = int.parse(
        assistantMessage.id.replaceFirst('assistant-', ''),
      );

      expect(
        userMicros,
        equals(assistantMicros),
        reason:
            'user and assistant message IDs must share the same correlation timestamp',
      );
      expect(userMessage.sessionId, equals(assistantMessage.sessionId));
      expect(userMessage.createdAt.microsecondsSinceEpoch, equals(userMicros));
      expect(
        assistantMessage.createdAt.microsecondsSinceEpoch,
        greaterThanOrEqualTo(assistantMicros),
        reason:
            'assistant reply is created later but must preserve the original correlation id seed',
      );
    },
  );
}
