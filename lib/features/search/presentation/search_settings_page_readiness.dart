part of 'search_settings_page.dart';

class _SemanticReadinessCard extends ConsumerWidget {
  const _SemanticReadinessCard({
    required this.readiness,
    required this.scope,
    required this.indexStatus,
    required this.summary,
    required this.refreshSession,
  });

  final SemanticSearchReadiness readiness;
  final SearchScopeConfig scope;
  final SearchIndexStatus indexStatus;
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
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = readiness.ready;
    final guidanceItems = _blockedGuidanceItems();

    return Card(
      color: isReady
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isReady ? Icons.auto_awesome : Icons.info_outline),
                const SizedBox(width: 8),
                Text(
                  summary.headline,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(summary.description),
            if (refreshSession.refreshing &&
                refreshSession.message != null) ...[
              const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (readiness.activeEmbeddingModel != null) ...[
                    Text(
                      '当前语义链路能力',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      readiness.activeEmbeddingModel!.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatModelCapabilitySummary(
                        readiness.activeEmbeddingModel!,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatSearchSettingsDeploymentStatus(
                        readiness.activeEmbeddingModel!,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '已启用本地 embedding 召回链路，可继续用于占位语义检索与索引构建。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (readiness.activeEmbeddingModel != null)
                    const SizedBox(height: 12),
                  Text(
                    '本地语义链路阶段概览',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._pipelineStages().map(
                    (stage) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        stage,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  if (guidanceItems.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '下一步可执行操作',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in guidanceItems)
                          if (item.route != null ||
                              item.action == _GuidanceAction.indexPending)
                            ActionChip(
                              label: Text(item.label),
                              onPressed: () {
                                if (item.route != null) {
                                  context.push(item.route!);
                                  return;
                                }

                                if (item.action ==
                                    _GuidanceAction.indexPending) {
                                  _handleIndexAction(context, ref);
                                }
                              },
                            )
                          else
                            Chip(label: Text(item.label)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _pipelineStages() {
    final modelStage = readiness.activeEmbeddingModel != null
        ? '已完成 · 模型选择：已完成'
        : '阻塞 · 模型选择：未完成';
    final scopeStage = scope.allowLocalEmbedding
        ? '已完成 · 检索范围：已启用本地语义检索'
        : '阻塞 · 检索范围：未启用本地语义检索';
    final indexStage = indexStatus.readyForIndexing
        ? '已完成 · 索引状态：可立即构建或刷新本地索引'
        : '阻塞 · 索引状态：当前仍存在阻塞项';
    return [modelStage, scopeStage, indexStage];
  }

  List<_GuidanceItem> _blockedGuidanceItems() {
    final items = <_GuidanceItem>[];

    if (readiness.activeEmbeddingModel == null) {
      items.add(
        const _GuidanceItem(
          label: '前往模型管理选择语义模型',
          route: AppDestination.models,
        ),
      );
    }
    if (!scope.allowLocalEmbedding) {
      items.add(const _GuidanceItem(label: '启用检索范围中的本地语义检索'));
    }
    if (indexStatus.readyForIndexing && indexStatus.hasPending) {
      items.add(
        _GuidanceItem(
          label: indexStatus.taskState.lastCompletedAt == null
              ? '立即构建索引'
              : '刷新索引',
          action: _GuidanceAction.indexPending,
        ),
      );
    }

    return items;
  }
}

enum _GuidanceAction { indexPending }

class _GuidanceItem {
  const _GuidanceItem({required this.label, this.route, this.action});

  final String label;
  final String? route;
  final _GuidanceAction? action;
}
