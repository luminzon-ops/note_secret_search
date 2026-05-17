import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_session.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_session_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_chat/presentation/chat_runtime_banner.dart';
import 'package:note_secret_search/features/ai_chat/presentation/free_chat_tab.dart';
import 'package:note_secret_search/features/ai_chat/presentation/private_qa_tab.dart';

class AiChatPage extends ConsumerWidget {
  AiChatPage({super.key});

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPhoneLayout = MediaQuery.sizeOf(context).width < 840;
    final readinessAsync = ref.watch(localLlmReadinessProvider);
    final externalStatusAsync = ref.watch(externalProviderStatusProvider);
    final sessionsAsync = ref.watch(chatSessionsProvider);
    final currentSessionId = ref.watch(currentChatSessionIdProvider);
    final currentSessionAsync = ref.watch(currentChatSessionProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('AI 问答'),
          leading: isPhoneLayout
              ? IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: '打开最近会话',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                )
              : null,
          bottom: const TabBar(
            tabs: [
              Tab(text: '私密内容问答'),
              Tab(text: '自由聊天'),
            ],
          ),
        ),
        drawer: isPhoneLayout
            ? Drawer(
                child: sessionsAsync.when(
                  data: (sessions) => _SessionListPanel(
                    sessions: sessions,
                    currentSessionId: currentSessionId,
                    closeAfterSelect: true,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  loading: () => const _SessionListPanelLoading(),
                  error: (error, stackTrace) => Center(child: Text(error.toString())),
                ),
              )
            : null,
        body: readinessAsync.when(
          data: (readiness) => externalStatusAsync.when(
            data: (externalStatus) {
              if (isPhoneLayout) {
                return Column(
                  children: [
                    currentSessionAsync.when(
                      data: (session) {
                        final targetIndex = switch (session?.mode) {
                          ChatMode.freeChat => 1,
                          _ => 0,
                        };
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final controller = DefaultTabController.maybeOf(context);
                          if (controller != null && controller.index != targetIndex) {
                            controller.animateTo(targetIndex);
                          }
                        });
                        return const SizedBox.shrink();
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (error, stackTrace) => const SizedBox.shrink(),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ChatRuntimeBanner(
                        readiness: readiness,
                        externalStatus: externalStatus,
                      ),
                    ),
                    const Expanded(
                      child: TabBarView(
                        children: [
                          PrivateQaTab(),
                          FreeChatTab(),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: sessionsAsync.when(
                      data: (sessions) => _SessionListPanel(
                        sessions: sessions,
                        currentSessionId: currentSessionId,
                      ),
                      loading: () => const _SessionListPanelLoading(),
                      error: (error, stackTrace) => Center(child: Text(error.toString())),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        currentSessionAsync.when(
                          data: (session) {
                            final targetIndex = switch (session?.mode) {
                              ChatMode.freeChat => 1,
                              _ => 0,
                            };
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final controller = DefaultTabController.maybeOf(context);
                              if (controller != null && controller.index != targetIndex) {
                                controller.animateTo(targetIndex);
                              }
                            });
                            return const SizedBox.shrink();
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (error, stackTrace) => const SizedBox.shrink(),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: ChatRuntimeBanner(
                            readiness: readiness,
                            externalStatus: externalStatus,
                          ),
                        ),
                        const Expanded(
                          child: TabBarView(
                            children: [
                              PrivateQaTab(),
                              FreeChatTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(child: Text(error.toString())),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
        ),
      ),
    );
  }
}

class _SessionListPanel extends ConsumerWidget {
  const _SessionListPanel({
    required this.sessions,
    required this.currentSessionId,
    this.closeAfterSelect = false,
    this.onClose,
  });

  final List<ChatSession> sessions;
  final String? currentSessionId;
  final bool closeAfterSelect;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('最近会话', style: Theme.of(context).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.add_comment_outlined),
          title: const Text('新建会话'),
          onTap: () async {
            final tabIndex = DefaultTabController.maybeOf(context)?.index ?? 0;
            final controller = tabIndex == 1
                ? ref.read(freeChatControllerProvider.notifier)
                : ref.read(privateQaChatControllerProvider.notifier);
            await controller.startNewSession();
            if (closeAfterSelect) {
              onClose?.call();
            }
          },
        ),
        const Divider(height: 1),
        if (sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('暂无会话'),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final selected = session.id == currentSessionId;
                return ListTile(
                  selected: selected,
                  title: Text(session.title),
                  subtitle: Text(DateFormat('MM-dd HH:mm').format(session.updatedAt)),
                  onTap: () async {
                    final controller = switch (session.mode) {
                      ChatMode.freeChat => ref.read(freeChatControllerProvider.notifier),
                      ChatMode.privateQa => ref.read(privateQaChatControllerProvider.notifier),
                    };
                    await controller.selectSession(session.id);
                    if (closeAfterSelect) {
                      onClose?.call();
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SessionListPanelLoading extends StatelessWidget {
  const _SessionListPanelLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
