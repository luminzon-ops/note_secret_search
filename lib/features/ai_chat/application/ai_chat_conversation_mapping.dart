part of 'ai_chat_providers.dart';

List<ChatContextItem> _mapSecretsToContextItems(List<SecretItem> secrets) {
  return secrets
      .map(
        (item) => ChatContextItem(
          id: item.id,
          type: ChatContextItemType.secret,
          title: item.title,
          preview: item.tags.isEmpty ? '私密条目' : item.tags.join('、'),
          summary: '手动选择的私密条目：${item.title}',
        ),
      )
      .toList(growable: false);
}

List<ChatContextItem> _mapNotesToContextItems(List<NoteItem> notes) {
  return notes
      .map(
        (item) => ChatContextItem(
          id: item.id,
          type: ChatContextItemType.note,
          title: item.title,
          preview: item.tags.isEmpty ? '私密笔记' : item.tags.join('、'),
          summary: '手动选择的私密笔记：${item.title}',
        ),
      )
      .toList(growable: false);
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
    backendUsage: message.backendUsage,
  );
}

List<ChatHistoryTurn> _buildChatHistory(List<ChatMessage> messages) {
  final turns = <ChatHistoryTurn>[];
  ChatMessage? pendingUser;
  for (final message in messages) {
    if (message.status != ChatMessageStatus.completed ||
        message.role == ChatMessageRole.system) {
      continue;
    }
    if (message.role == ChatMessageRole.user) {
      pendingUser = message;
      continue;
    }
    if (message.role == ChatMessageRole.assistant && pendingUser != null) {
      turns.add(
        ChatHistoryTurn(
          userText: pendingUser.text,
          assistantText: message.text,
          usedPrivateContext: message.usedPrivateContext,
          usage: message.backendUsage,
        ),
      );
      pendingUser = null;
    }
  }
  return List<ChatHistoryTurn>.unmodifiable(turns);
}

String _safeChatErrorMessage(
  Object error,
  ChatBackendPreference backendPreference,
) {
  if (error is ExternalChatGatewayException) {
    return error.message;
  }
  if (error is ChatPromptException) {
    return error.message;
  }
  if (error is AiChatCancelledException) {
    return error.toString();
  }
  return switch (backendPreference) {
    ChatBackendPreference.local => '本地模型请求失败，请稍后重试。',
    ChatBackendPreference.external => '外部模型请求失败，请稍后重试。',
  };
}

class _SendingChatOperation {
  const _SendingChatOperation({required this.requestId});

  final String requestId;
}
