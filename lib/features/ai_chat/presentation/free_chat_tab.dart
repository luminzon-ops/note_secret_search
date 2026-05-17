import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/presentation/chat_input_bar.dart';
import 'package:note_secret_search/features/ai_chat/presentation/external_privacy_confirmation.dart';
import 'package:note_secret_search/features/ai_chat/presentation/chat_message_list.dart';
import 'package:note_secret_search/features/ai_chat/presentation/manual_context_picker_sheet.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';

class FreeChatTab extends ConsumerWidget {
  const FreeChatTab({super.key});

  Future<void> _handleSend(BuildContext context, WidgetRef ref, String value) async {
    final state = ref.read(freeChatControllerProvider);
    final externalStatus = await ref.read(externalProviderStatusProvider.future);
    if (!context.mounted) {
      return;
    }
    final shouldConfirm = externalStatus.available &&
        externalStatus.config != null &&
        state.allowPrivateContext;

    if (shouldConfirm) {
      final confirmed = await confirmExternalPrivateContextSend(context: context, ref: ref);
      if (!confirmed) {
        return;
      }
    }

    await ref.read(freeChatControllerProvider.notifier).send(value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(freeChatControllerProvider);
    final controller = ref.read(freeChatControllerProvider.notifier);
    final semanticReadinessAsync = ref.watch(freeChatSemanticReadinessProvider);

    Future.microtask(controller.restoreSessionIfNeeded);

    return Column(
      children: [
        SwitchListTile(
          title: const Text('允许参考私密内容'),
          value: state.allowPrivateContext,
          onChanged: state.sending ? null : controller.setAllowPrivateContext,
        ),
        if (state.allowPrivateContext)
          semanticReadinessAsync.when(
            data: (semanticReadiness) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!semanticReadiness.ready)
                    Text(
                      semanticReadiness.reason,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: state.sending
                            ? null
                            : () async {
                                final selected = await showModalBottomSheet<List<ChatContextItem>>(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (context) => ManualContextPickerSheet(
                                    initialIds: state.manualItems.map((item) => item.id).toSet(),
                                  ),
                                );
                                if (selected != null) {
                                  controller.setManualItems(selected);
                                }
                              },
                        child: const Text('手动选择私密内容'),
                      ),
                      if (state.manualItems.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '已选择 ${state.manualItems.length} 项',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(error.toString()),
            ),
          ),
        Expanded(child: ChatMessageList(messages: state.messages)),
        ChatInputBar(
          enabled: !state.sending,
          sending: state.sending,
          hintText: '输入你的问题或消息',
          onSend: (value) => _handleSend(context, ref, value),
        ),
      ],
    );
  }
}
