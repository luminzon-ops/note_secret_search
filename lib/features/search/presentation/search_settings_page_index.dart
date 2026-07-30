part of 'search_settings_page.dart';

class _IndexSettingsCard extends ConsumerWidget {
  const _IndexSettingsCard({
    required this.settings,
    required this.onChanged,
    required this.onSave,
  });

  final SearchIndexSettings settings;
  final ValueChanged<SearchIndexSettings> onChanged;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('语义索引设置', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '将范围控制、索引策略与模型可用性集中管理，避免主搜索页承载过多配置。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.autoIndexEnabled,
              title: const Text('保存后自动索引'),
              onChanged: (value) =>
                  onChanged(settings.copyWith(autoIndexEnabled: value)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('单 chunk 最大长度'),
              subtitle: Text('${settings.maxChunkLength} 字符'),
              trailing: DropdownButton<int>(
                value: settings.maxChunkLength,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  onChanged(settings.copyWith(maxChunkLength: value));
                },
                items: const [
                  DropdownMenuItem(value: 160, child: Text('160')),
                  DropdownMenuItem(value: 280, child: Text('280')),
                  DropdownMenuItem(value: 400, child: Text('400')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onSave,
                child: const Text('保存索引设置'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndexStatusCard extends ConsumerWidget {
  const _IndexStatusCard({
    required this.status,
    required this.summary,
    required this.refreshSession,
  });

  final SearchIndexStatus status;
  final SearchStatusSummary summary;
  final SearchRefreshSessionState refreshSession;

  Future<void> _handleIndexAction(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!status.hasPending) {
      messenger.showSnackBar(
        const SnackBar(content: Text('当前没有待索引内容，无需手动触发构建。')),
      );
      return;
    }

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
        const SnackBar(content: Text('已开始处理待索引内容，请稍后查看最新结果。')),
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
    final lastRunSummary = _lastRunSummary(status.taskState);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('语义索引状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(status.engineReason),
            const SizedBox(height: 8),
            if (status.taskState.running)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('自动索引中'),
                subtitle: Text('正在构建或刷新占位语义索引。'),
              )
            else if (status.taskState.lastCompletedAt != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_outlined),
                title: Text('最近索引：${status.taskState.lastIndexedCount} 项'),
                subtitle: Text(
                  status.taskState.lastCompletedAt!.toLocal().toString(),
                ),
                trailing: status.taskState.lastError == null
                    ? const Text('成功')
                    : const Text('有错误'),
              ),
            if (status.taskState.running) ...[
              const SizedBox(height: 8),
              Text(
                '当前状态：正在构建索引',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              const Text('系统正在处理待索引内容，完成后会自动刷新这里的摘要。'),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                '当前状态：${summary.headline}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(summary.description),
            ],
            if (lastRunSummary != null) ...[
              const SizedBox(height: 12),
              Text('最近结果摘要', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(lastRunSummary),
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
            if (status.taskState.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                status.taskState.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            Text('待索引项目：${status.pendingCount}'),
            const SizedBox(height: 8),
            Text(_pendingSummary(status.pendingItems)),
            if (summary.phase == SearchStatusPhase.ready) ...[
              const SizedBox(height: 12),
              const Text('当前索引已最新，可以直接继续使用语义检索。'),
            ],
            if (status.hasPending) ...[
              const SizedBox(height: 8),
              Text('最近变更项', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final item in status.pendingItems.take(3))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.sourceType == SearchSourceType.secret
                        ? Icons.lock_outline
                        : Icons.note_outlined,
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.updatedAt.toLocal().toString()),
                ),
            ],
            if (summary.primaryAction ==
                    SearchStatusPrimaryAction.triggerIndex &&
                summary.primaryActionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: refreshSession.refreshing
                    ? null
                    : () => _handleIndexAction(context, ref),
                icon: refreshSession.refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high_outlined),
                label: Text(summary.primaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _pendingSummary(List<SearchIndexPendingItem> items) {
    var secretCount = 0;
    var noteCount = 0;
    for (final item in items) {
      switch (item.sourceType) {
        case SearchSourceType.secret:
          secretCount++;
          break;
        case SearchSourceType.note:
          noteCount++;
          break;
      }
    }

    final segments = <String>[];
    if (secretCount > 0) {
      segments.add('密码 $secretCount 项');
    }
    if (noteCount > 0) {
      segments.add('笔记 $noteCount 项');
    }
    if (segments.isEmpty) {
      return '待索引摘要：暂无待处理项';
    }
    return '待索引摘要：${segments.join('，')}';
  }

  String? _lastRunSummary(SearchIndexTaskState taskState) {
    if (taskState.lastCompletedAt == null) {
      return null;
    }

    if (taskState.lastError != null) {
      return '最近一次完成 0 项，仍有错误需要处理。';
    }

    return '最近一次完成 ${taskState.lastIndexedCount} 项，当前无错误。';
  }
}
