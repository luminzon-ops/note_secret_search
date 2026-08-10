part of 'search_settings_page.dart';

class _SearchScopeCard extends ConsumerWidget {
  const _SearchScopeCard({
    required this.scope,
    required this.onChanged,
    required this.onSave,
  });

  final SearchScopeConfig scope;
  final ValueChanged<SearchScopeConfig> onChanged;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('检索范围控制', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '保守默认：敏感字段是否进入关键词检索或语义检索都由这里统一控制。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeTitle,
              title: const Text('检索标题'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(includeTitle: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeUsername,
              title: const Text('账号字段'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(includeUsername: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includePasswordField,
              title: const Text('密码字段'),
              subtitle: const Text('仅用于关键词检索，不进入语义索引或 AI 自动上下文。'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(includePasswordField: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeUrl,
              title: const Text('网址字段'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(includeUrl: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeSecretNote,
              title: const Text('密码附注'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(includeSecretNote: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeTags,
              title: const Text('标签'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(includeTags: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeNoteBody,
              title: const Text('笔记摘要与正文'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(includeNoteBody: value)),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.allowLocalEmbedding,
              title: const Text('允许本地语义检索'),
              subtitle: const Text('关闭后语义检索与 AI 自动上下文停用，并清理本地派生索引。'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(allowLocalEmbedding: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.allowExternalProviderAccess,
              title: const Text('允许外部模型访问'),
              subtitle: const Text('关闭时，后续外部 Provider 不得读取当前查询与内容。'),
              onChanged: (value) =>
                  onChanged(scope.copyWith(allowExternalProviderAccess: value)),
            ),
            if (scope.allowExternalProviderAccess) ...[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '隐私提示：开启后，后续接入的外部模型 Provider 可能读取当前检索请求与授权范围内的内容。MVP 阶段默认建议保持关闭。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onSave,
                child: const Text('保存检索范围'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
