part of 'ai_chat_providers.dart';

void _invalidateSelectedChatSession(Ref ref) {
  ref.invalidate(currentChatMessagesProvider);
  ref.invalidate(currentChatSessionProvider);
}

List<ChatMessage> _replaceChatMessageById({
  required List<ChatMessage> messages,
  required String targetId,
  required ChatMessage replacement,
}) {
  final index = messages.indexWhere((message) => message.id == targetId);
  if (index == -1) {
    return [...messages, replacement];
  }

  return [...messages.take(index), replacement, ...messages.skip(index + 1)];
}

ChatMessage _mapStoredChatMessageToUi(ChatStoredMessage message) {
  return ChatMessage(
    id: message.id,
    role: switch (message.role) {
      ChatStoredMessageRole.user => ChatMessageRole.user,
      ChatStoredMessageRole.assistant => ChatMessageRole.assistant,
      ChatStoredMessageRole.system => ChatMessageRole.system,
    },
    text: message.content,
    createdAt: message.createdAt,
    status: switch (message.status) {
      ChatStoredMessageStatus.loading => ChatMessageStatus.loading,
      ChatStoredMessageStatus.completed => ChatMessageStatus.completed,
      ChatStoredMessageStatus.failed => ChatMessageStatus.error,
    },
    usedPrivateContext: message.usedPrivateContext,
    contextSummary:
        message.autoRetrievedContextSummary == null ||
            message.autoRetrievedContextSummary!.trim().isEmpty
        ? const <String>[]
        : message.autoRetrievedContextSummary!.split('；'),
  );
}
