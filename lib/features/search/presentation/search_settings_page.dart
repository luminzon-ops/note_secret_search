import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';

class SearchSettingsPage extends ConsumerWidget {
  const SearchSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeAsync = ref.watch(searchScopeConfigProvider);
    final semanticReadinessAsync = ref.watch(semanticSearchReadinessProvider);
    final indexStatusAsync = ref.watch(searchIndexStatusProvider);
    final indexSettingsAsync = ref.watch(searchIndexSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('搜索与索引设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (semanticReadinessAsync.hasValue && scopeAsync.hasValue && indexStatusAsync.hasValue)
            _SemanticReadinessCard(
              readiness: semanticReadinessAsync.requireValue,
              scope: scopeAsync.requireValue,
              indexStatus: indexStatusAsync.requireValue,
            )
          else if (semanticReadinessAsync.hasError)
            Text(semanticReadinessAsync.error.toString())
          else if (scopeAsync.hasError)
            Text(scopeAsync.error.toString())
          else if (indexStatusAsync.hasError)
            Text(indexStatusAsync.error.toString())
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          indexStatusAsync.when(
            data: (status) => _IndexStatusCard(status: status),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          indexSettingsAsync.when(
            data: (settings) => _IndexSettingsCard(settings: settings),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          scopeAsync.when(
            data: (scope) => _SearchScopeCard(scope: scope),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(error.toString()),
          ),
        ],
      ),
    );
  }
}

class _IndexSettingsCard extends ConsumerWidget {
  const _IndexSettingsCard({required this.settings});

  final SearchIndexSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchIndexSettingsControllerProvider);

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
              onChanged: (value) => controller.update(settings.copyWith(autoIndexEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.includeSecretNotes,
              title: const Text('索引密码附注'),
              onChanged: (value) => controller.update(settings.copyWith(includeSecretNotes: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.includeNoteBody,
              title: const Text('索引笔记正文'),
              onChanged: (value) => controller.update(settings.copyWith(includeNoteBody: value)),
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
                  controller.update(settings.copyWith(maxChunkLength: value));
                },
                items: const [
                  DropdownMenuItem(value: 160, child: Text('160')),
                  DropdownMenuItem(value: 280, child: Text('280')),
                  DropdownMenuItem(value: 400, child: Text('400')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndexStatusCard extends ConsumerWidget {
  const _IndexStatusCard({required this.status});

  final SearchIndexStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                subtitle: Text(status.taskState.lastCompletedAt!.toLocal().toString()),
                trailing: status.taskState.lastError == null
                    ? const Text('成功')
                    : const Text('有错误'),
              ),
            if (status.taskState.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                status.taskState.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            Text('待索引项目：${status.pendingItems.length}'),
            if (status.pendingItems.isNotEmpty) ...[
              const SizedBox(height: 8),
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
            if (status.readyForIndexing && status.pendingItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => ref.read(searchIndexControllerProvider).indexPending(),
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('构建占位索引'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SemanticReadinessCard extends ConsumerWidget {
  const _SemanticReadinessCard({
    required this.readiness,
    required this.scope,
    required this.indexStatus,
  });

  final SemanticSearchReadiness readiness;
  final SearchScopeConfig scope;
  final SearchIndexStatus indexStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = readiness.ready;
    final guidanceItems = _blockedGuidanceItems();

    return Card(
      color: isReady ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
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
                  isReady ? '本地语义检索已就绪' : '本地语义检索未就绪',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(readiness.reason),
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
                      '当前语义能力',
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
                      _modelSummary(readiness.activeEmbeddingModel!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '已启用本地 embedding 召回链路，可继续用于占位语义检索与索引构建。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (readiness.activeEmbeddingModel != null) const SizedBox(height: 12),
                  Text(
                    '本地语义链路阶段',
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
                      '下一步建议',
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
                          if (item.route != null || item.action == _GuidanceAction.indexPending)
                            ActionChip(
                              label: Text(item.label),
                              onPressed: () {
                                if (item.route != null) {
                                  context.push(item.route!);
                                  return;
                                }

                                if (item.action == _GuidanceAction.indexPending) {
                                  ref.read(searchIndexControllerProvider).indexPending();
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

  String _modelSummary(ModelRegistryEntry model) {
    final segments = <String>[model.provider, model.type];
    if (model.quantization != null && model.quantization!.isNotEmpty) {
      segments.add(model.quantization!);
    }
    return segments.join(' · ');
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
      items.add(const _GuidanceItem(label: '前往模型管理', route: '/models'));
    }
    if (!scope.allowLocalEmbedding) {
      items.add(const _GuidanceItem(label: '启用本地语义检索'));
    }
    if (indexStatus.readyForIndexing && indexStatus.pendingItems.isNotEmpty) {
      items.add(
        _GuidanceItem(
          label: indexStatus.taskState.lastCompletedAt == null ? '立即构建索引' : '刷新本地索引',
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

class _SearchScopeCard extends ConsumerWidget {
  const _SearchScopeCard({required this.scope});

  final SearchScopeConfig scope;

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
              title: const Text('标题'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(includeTitle: value),
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeUsername,
              title: const Text('账号字段'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(includeUsername: value),
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includePasswordField,
              title: const Text('密码字段'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(includePasswordField: value),
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeUrl,
              title: const Text('网址字段'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(includeUrl: value),
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeSecretNote,
              title: const Text('密码附注'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(includeSecretNote: value),
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeTags,
              title: const Text('标签'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(includeTags: value),
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeNoteBody,
              title: const Text('笔记正文'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(includeNoteBody: value),
                  ),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.allowLocalEmbedding,
              title: const Text('允许本地语义检索'),
              subtitle: const Text('当前版本仍为占位 embedding 引擎，仅先打通搜索流程。'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(allowLocalEmbedding: value),
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.allowExternalProviderAccess,
              title: const Text('允许外部模型访问'),
              subtitle: const Text('关闭时，后续外部 Provider 不得读取当前查询与内容。'),
              onChanged: (value) => ref.read(searchScopeControllerProvider).update(
                    scope.copyWith(allowExternalProviderAccess: value),
                  ),
            ),
            if (scope.allowExternalProviderAccess) ...[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
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
          ],
        ),
      ),
    );
  }
}
