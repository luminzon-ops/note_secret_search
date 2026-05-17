import 'package:flutter/material.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_message.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({required this.messages, super.key});

  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(child: Text('消息区骨架'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final message = messages[index];
        final isUser = message.role == ChatMessageRole.user;
        final color = switch (message.role) {
          ChatMessageRole.user => Theme.of(context).colorScheme.primaryContainer,
          ChatMessageRole.assistant => Theme.of(context).colorScheme.surfaceContainerHighest,
          ChatMessageRole.system => Theme.of(context).colorScheme.errorContainer,
        };
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              color: color,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message.text),
                    if (message.status == ChatMessageStatus.loading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    if (message.usedPrivateContext) ...[
                      const SizedBox(height: 8),
                      const Text('本次回答基于本地私密内容生成'),
                    ],
                    if (message.contextSummary.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...message.contextSummary.map(
                        (summary) => Text(
                          summary,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemCount: messages.length,
    );
  }
}
