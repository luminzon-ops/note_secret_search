part of 'search_page.dart';

class _SearchStatusCard extends ConsumerWidget {
  const _SearchStatusCard({
    required this.summary,
    required this.refreshSession,
  });

  final SearchStatusSummary summary;
  final SearchRefreshSessionState refreshSession;

  Future<void> _handleIndexAction(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(searchRefreshControllerProvider.notifier)
          .refresh(ref.read(searchQueryProvider));
      if (result != SearchRefreshExecutionResult.completed) {
        return;
      }
      if (!messenger.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('已开始构建索引，请稍后刷新搜索结果。')),
      );
    } catch (_) {
      if (!messenger.mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('索引触发失败，请稍后重试。')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.headline,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(summary.description),
            if (summary.pendingCount > 0) ...[
              const SizedBox(height: 8),
              Text('待索引内容：${summary.pendingCount} 项'),
            ],
            if (summary.lastResultSummary != null) ...[
              const SizedBox(height: 8),
              Text(
                summary.lastResultSummary!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (refreshSession.refreshing &&
                refreshSession.message != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(refreshSession.message!)),
                ],
              ),
            ],
            if (summary.errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                summary.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (summary.primaryAction != SearchStatusPrimaryAction.none &&
                summary.primaryActionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: refreshSession.refreshing
                    ? null
                    : () {
                        switch (summary.primaryAction) {
                          case SearchStatusPrimaryAction.openModelManagement:
                            context.push(AppDestination.models);
                            break;
                          case SearchStatusPrimaryAction.triggerIndex:
                            _handleIndexAction(context, ref);
                            break;
                          case SearchStatusPrimaryAction.none:
                            break;
                        }
                      },
                icon: refreshSession.refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        summary.primaryAction ==
                                SearchStatusPrimaryAction.openModelManagement
                            ? Icons.memory_outlined
                            : Icons.auto_fix_high_outlined,
                      ),
                label: Text(summary.primaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchRefreshFeedbackCard extends StatelessWidget {
  const _SearchRefreshFeedbackCard({required this.feedback});

  final SearchRefreshFeedbackState feedback;

  @override
  Widget build(BuildContext context) {
    final icon = feedback.changed == true
        ? Icons.check_circle_outline
        : Icons.info_outline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (feedback.headline != null)
                    Text(
                      feedback.headline!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (feedback.headline != null && feedback.message != null)
                    const SizedBox(height: 8),
                  if (feedback.message != null) Text(feedback.message!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPendingReindexHandoffCard extends ConsumerWidget {
  const _SearchPendingReindexHandoffCard({required this.handoff});

  final SearchPendingReindexHandoffState handoff;

  Future<void> _handleRefresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(searchRefreshControllerProvider.notifier)
          .refresh(ref.read(searchQueryProvider));
      if (result != SearchRefreshExecutionResult.completed) {
        return;
      }
    } catch (_) {
      if (!messenger.mounted) {
        return;
      }
      messenger.showSnackBar(const SnackBar(content: Text('索引触发失败，请稍后重试。')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设置已保存，但语义结果还没刷新',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(handoff.message ?? '你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。'),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: ref.watch(searchRefreshSessionProvider).refreshing
                  ? null
                  : () => _handleRefresh(context, ref),
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('立即刷新索引'),
            ),
          ],
        ),
      ),
    );
  }
}
