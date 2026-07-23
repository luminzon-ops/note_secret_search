import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_context_projector.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_prompt_composer.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_backend_usage.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';

void main() {
  const composer = ChatPromptComposer();

  test(
    'local prompt stays bounded and always preserves the current question',
    () {
      const question = 'CURRENT_QUESTION_SENTINEL';
      final result = composer.compose(
        mode: ChatMode.freeChat,
        question: question,
        target: ChatPromptTarget.local,
        manualItems: <ProjectedChatContextItem>[
          ProjectedChatContextItem(
            type: ChatContextItemType.note,
            title: 'Manual',
            content: 'MANUAL_SENTINEL ${'m' * 850}',
          ),
        ],
        history: <ChatHistoryTurn>[
          ChatHistoryTurn(
            userText: 'OLD_USER_SENTINEL ${'u' * 350}',
            assistantText: 'OLD_ASSISTANT_SENTINEL ${'a' * 350}',
            usedPrivateContext: false,
          ),
        ],
        autoItems: const <ChatContextItem>[
          ChatContextItem(
            id: 'auto-1',
            type: ChatContextItemType.note,
            title: 'Auto',
            preview: 'preview',
            summary: 'AUTO_SENTINEL',
          ),
        ],
      );

      expect(result.prompt.length, lessThanOrEqualTo(1200));
      expect(result.prompt, contains(question));
      expect(result.prompt, contains('MANUAL_SENTINEL'));
      expect(result.prompt, isNot(contains('OLD_USER_SENTINEL')));
    },
  );

  test('oversized current question fails instead of truncating', () {
    final question = 'Q' * 1200;

    expect(
      () => composer.compose(
        mode: ChatMode.freeChat,
        question: question,
        target: ChatPromptTarget.local,
      ),
      throwsA(
        isA<ChatPromptException>().having(
          (error) => error.code,
          'code',
          'PROMPT_TOO_LARGE',
        ),
      ),
    );
  });

  test('history keeps at most six recent complete turns', () {
    final result = composer.compose(
      mode: ChatMode.freeChat,
      question: 'continue',
      target: ChatPromptTarget.local,
      history: List<ChatHistoryTurn>.generate(
        8,
        (index) => ChatHistoryTurn(
          userText: 'USER_${index + 1}',
          assistantText: 'ASSISTANT_${index + 1}',
          usedPrivateContext: false,
        ),
      ),
    );

    expect(result.includedHistoryTurns, 6);
    expect(result.prompt, isNot(contains('USER_1')));
    expect(result.prompt, isNot(contains('ASSISTANT_2')));
    for (var index = 3; index <= 8; index++) {
      expect(result.prompt, contains('USER_$index'));
      expect(result.prompt, contains('ASSISTANT_$index'));
    }
  });

  test(
    'external history requires the same fingerprint and allowed sensitivity',
    () {
      final result = composer.compose(
        mode: ChatMode.freeChat,
        question: 'continue',
        target: ChatPromptTarget.external,
        externalProviderFingerprint: 'fp-current',
        includesPrivateContext: false,
        history: const <ChatHistoryTurn>[
          ChatHistoryTurn(
            userText: 'SAME_STANDARD_USER',
            assistantText: 'SAME_STANDARD_ASSISTANT',
            usedPrivateContext: false,
            usage: ChatBackendUsage(
              actualBackend: 'openAiCompatible',
              actualModel: 'model',
              providerFingerprint: 'fp-current',
            ),
          ),
          ChatHistoryTurn(
            userText: 'SAME_PRIVATE_USER',
            assistantText: 'SAME_PRIVATE_ASSISTANT',
            usedPrivateContext: true,
            usage: ChatBackendUsage(
              actualBackend: 'openAiCompatible',
              actualModel: 'model',
              providerFingerprint: 'fp-current',
            ),
          ),
          ChatHistoryTurn(
            userText: 'OTHER_PROVIDER_USER',
            assistantText: 'OTHER_PROVIDER_ASSISTANT',
            usedPrivateContext: false,
            usage: ChatBackendUsage(
              actualBackend: 'openAiCompatible',
              actualModel: 'model',
              providerFingerprint: 'fp-other',
            ),
          ),
          ChatHistoryTurn(
            userText: 'LOCAL_USER',
            assistantText: 'LOCAL_ASSISTANT',
            usedPrivateContext: false,
          ),
        ],
      );

      expect(result.prompt, contains('SAME_STANDARD_USER'));
      expect(result.prompt, contains('SAME_STANDARD_ASSISTANT'));
      expect(result.prompt, isNot(contains('SAME_PRIVATE_USER')));
      expect(result.prompt, isNot(contains('OTHER_PROVIDER_USER')));
      expect(result.prompt, isNot(contains('LOCAL_USER')));
    },
  );
}
