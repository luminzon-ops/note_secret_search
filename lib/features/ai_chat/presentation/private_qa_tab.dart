import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/presentation/chat_input_bar.dart';
import 'package:note_secret_search/features/ai_chat/presentation/chat_message_list.dart';
import 'package:note_secret_search/features/ai_chat/presentation/external_privacy_confirmation.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';

class PrivateQaTab extends ConsumerWidget {
  const PrivateQaTab({super.key});

  Future<void> _handleSend(BuildContext context, WidgetRef ref, String value) async {
    final externalStatus = await ref.read(externalProviderStatusProvider.future);
    if (!context.mounted) {
      return;
    }
    final shouldConfirm = externalStatus.available && externalStatus.config != null;

    if (shouldConfirm) {
      final confirmed = await confirmExternalPrivateContextSend(context: context, ref: ref);
      if (!confirmed) {
        return;
      }
    }

    await ref.read(privateQaChatControllerProvider.notifier).send(value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(privateQaChatControllerProvider);
    final controller = ref.read(privateQaChatControllerProvider.notifier);
    final showPrivateNotice = state.messages.any((message) => message.usedPrivateContext);
    final semanticReadinessAsync = ref.watch(privateQaSemanticReadinessProvider);

    Future.microtask(controller.restoreSessionIfNeeded);

    return semanticReadinessAsync.when(
      data: (semanticReadiness) => Column(
        children: [
          if (!semanticReadiness.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(semanticReadiness.reason),
              ),
            ),
          if (showPrivateNotice)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('本次回答基于本地私密内容生成'),
              ),
            ),
          Expanded(child: ChatMessageList(messages: state.messages)),
          ChatInputBar(
            enabled: !state.sending && semanticReadiness.ready,
            sending: state.sending,
            hintText: '输入你的私密内容问题',
            onSend: (value) => _handleSend(context, ref, value),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text(error.toString())),
    );
  }
}
