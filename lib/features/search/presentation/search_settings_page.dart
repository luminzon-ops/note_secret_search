import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_presentation_formatter.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/presentation/search_settings_impact_preview.dart';
import 'package:note_secret_search/features/search/presentation/search_status_summary.dart';

class SearchSettingsPage extends ConsumerStatefulWidget {
  const SearchSettingsPage({super.key});

  @override
  ConsumerState<SearchSettingsPage> createState() => _SearchSettingsPageState();
}

class _SearchSettingsPageState extends ConsumerState<SearchSettingsPage> {
  SearchScopeConfig? _draftScope;
  SearchIndexSettings? _draftIndexSettings;
  bool _showPostSaveReindexActions = false;

  Future<void> _triggerPostSaveRefresh(BuildContext context) async {
    try {
      await ref.read(searchIndexControllerProvider).indexPendingAndRefresh();
      if (!context.mounted) {
        return;
      }
      setState(() => _showPostSaveReindexActions = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始处理待索引内容，请稍后查看最新结果。')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('索引触发失败，请稍后重试。')),
      );
    }
  }

  void _returnToSearch(BuildContext context) {
    ref.read(searchPendingReindexHandoffProvider.notifier).state =
        const SearchPendingReindexHandoffState(
          visible: true,
          message: '你刚保存了会影响语义索引的设置。刷新索引后，再判断当前语义结果会更准确。',
        );
    setState(() => _showPostSaveReindexActions = false);
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final scopeAsync = ref.watch(searchScopeConfigProvider);
    final semanticReadinessAsync = ref.watch(semanticSearchReadinessProvider);
    final indexStatusAsync = ref.watch(searchIndexStatusProvider);
    final indexSettingsAsync = ref.watch(searchIndexSettingsProvider);
    final refreshSession = ref.watch(searchRefreshSessionProvider);

    final savedScope = scopeAsync.valueOrNull;
    final savedIndexSettings = indexSettingsAsync.valueOrNull;
    if (savedScope != null && _draftScope == null) {
      _draftScope = savedScope;
    }
    if (savedIndexSettings != null && _draftIndexSettings == null) {
      _draftIndexSettings = savedIndexSettings;
    }

    final alignedSummary = semanticReadinessAsync.hasValue && indexStatusAsync.hasValue
        ? buildSearchStatusSummary(
            readiness: semanticReadinessAsync.requireValue,
            status: indexStatusAsync.requireValue,
          )
        : null;

    final impactPreview = savedScope != null &&
            savedIndexSettings != null &&
            _draftScope != null &&
            _draftIndexSettings != null &&
            indexStatusAsync.hasValue
        ? buildSearchSettingsImpactPreview(
            savedScope: savedScope,
            draftScope: _draftScope!,
            savedIndexSettings: savedIndexSettings,
            draftIndexSettings: _draftIndexSettings!,
            indexStatus: indexStatusAsync.requireValue,
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('搜索与索引设置')),
      bottomNavigationBar: _showPostSaveReindexActions && !refreshSession.refreshing
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '设置已保存，语义结果需要刷新索引后更新。',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: () => _triggerPostSaveRefresh(context),
                              child: const Text('立即刷新'),
                            ),
                            TextButton(
                              onPressed: () => _returnToSearch(context),
                              child: const Text('返回搜索'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (semanticReadinessAsync.hasValue && scopeAsync.hasValue && indexStatusAsync.hasValue)
            _SemanticReadinessCard(
              readiness: semanticReadinessAsync.requireValue,
              scope: scopeAsync.requireValue,
              indexStatus: indexStatusAsync.requireValue,
              summary: alignedSummary!,
              refreshSession: refreshSession,
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
            data: (status) => alignedSummary == null
                ? const SizedBox.shrink()
                : _IndexStatusCard(
                    status: status,
                    summary: alignedSummary,
                    refreshSession: refreshSession,
                  ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          if (impactPreview != null)
            _SearchSettingsImpactPreviewCard(preview: impactPreview)
          else
            const SizedBox.shrink(),
          const SizedBox(height: 16),
          indexSettingsAsync.when(
            data: (settings) => _IndexSettingsCard(
              settings: _draftIndexSettings ?? settings,
              onChanged: (next) => setState(() {
                _draftIndexSettings = next;
                _showPostSaveReindexActions = false;
              }),
              onSave: () async {
                final draft = _draftIndexSettings;
                final savedScopeSnapshot = savedScope;
                final savedSettingsSnapshot = savedIndexSettings;
                final indexStatusSnapshot = indexStatusAsync.valueOrNull;
                if (draft == null) {
                  return;
                }
                final needsReindex = savedScopeSnapshot != null &&
                    savedSettingsSnapshot != null &&
                    indexStatusSnapshot != null &&
                    buildSearchSettingsImpactPreview(
                          savedScope: savedScopeSnapshot,
                          draftScope: _draftScope ?? savedScopeSnapshot,
                          savedIndexSettings: savedSettingsSnapshot,
                          draftIndexSettings: draft,
                          indexStatus: indexStatusSnapshot,
                        ).reindexItems.isNotEmpty;
                await ref.read(searchIndexSettingsControllerProvider).update(draft);
                if (!mounted) {
                  return;
                }
                setState(() {
                  _draftIndexSettings = draft;
                  _showPostSaveReindexActions = needsReindex;
                });
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
          const SizedBox(height: 16),
          scopeAsync.when(
            data: (scope) => _SearchScopeCard(
              scope: _draftScope ?? scope,
              onChanged: (next) => setState(() {
                _draftScope = next;
                _showPostSaveReindexActions = false;
              }),
              onSave: () async {
                final draft = _draftScope;
                final savedScopeSnapshot = savedScope;
                final savedSettingsSnapshot = savedIndexSettings;
                final indexStatusSnapshot = indexStatusAsync.valueOrNull;
                if (draft == null) {
                  return;
                }
                final needsReindex = savedScopeSnapshot != null &&
                    savedSettingsSnapshot != null &&
                    indexStatusSnapshot != null &&
                    buildSearchSettingsImpactPreview(
                          savedScope: savedScopeSnapshot,
                          draftScope: draft,
                          savedIndexSettings: savedSettingsSnapshot,
                          draftIndexSettings: _draftIndexSettings ?? savedSettingsSnapshot,
                          indexStatus: indexStatusSnapshot,
                        ).reindexItems.isNotEmpty;
                await ref.read(searchScopeControllerProvider).update(draft);
                if (!mounted) {
                  return;
                }
                setState(() {
                  _draftScope = draft;
                  _showPostSaveReindexActions = needsReindex;
                });
              },
            ),
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
  const _IndexSettingsCard({required this.settings, required this.onChanged, required this.onSave});

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
              onChanged: (value) => onChanged(settings.copyWith(autoIndexEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.includeSecretNotes,
              title: const Text('索引密码附注'),
              onChanged: (value) => onChanged(settings.copyWith(includeSecretNotes: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.includeNoteBody,
              title: const Text('索引笔记正文'),
              onChanged: (value) => onChanged(settings.copyWith(includeNoteBody: value)),
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
    if (status.pendingItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有待索引内容，无需手动触发构建。')),
      );
      return;
    }

    try {
      await ref.read(searchIndexControllerProvider).indexPendingAndRefresh();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始处理待索引内容，请稍后查看最新结果。')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('索引触发失败，请稍后重试。')),
      );
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
                subtitle: Text(status.taskState.lastCompletedAt!.toLocal().toString()),
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
            if (refreshSession.refreshing && refreshSession.message != null) ...[
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
            Text('待索引项目：${status.pendingItems.length}'),
            const SizedBox(height: 8),
            Text(_pendingSummary(status.pendingItems)),
            if (summary.phase == SearchStatusPhase.ready) ...[
              const SizedBox(height: 12),
              const Text('当前索引已最新，可以直接继续使用语义检索。'),
            ],
            if (status.pendingItems.isNotEmpty) ...[
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
            if (summary.primaryAction == SearchStatusPrimaryAction.triggerIndex &&
                summary.primaryActionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: refreshSession.refreshing ? null : () => _handleIndexAction(context, ref),
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
    try {
      await ref.read(searchIndexControllerProvider).indexPendingAndRefresh();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始处理待索引内容，请稍后查看最新结果。')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('索引触发失败，请稍后重试。')),
      );
    }
  }

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
                  summary.headline,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(summary.description),
            if (refreshSession.refreshing && refreshSession.message != null) ...[
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
                      formatModelCapabilitySummary(readiness.activeEmbeddingModel!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatSearchSettingsDeploymentStatus(readiness.activeEmbeddingModel!),
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
                          if (item.route != null || item.action == _GuidanceAction.indexPending)
                            ActionChip(
                              label: Text(item.label),
                              onPressed: () {
                                 if (item.route != null) {
                                   context.push(item.route!);
                                   return;
                                 }

                                 if (item.action == _GuidanceAction.indexPending) {
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
      items.add(const _GuidanceItem(label: '前往模型管理选择语义模型', route: '/models'));
    }
    if (!scope.allowLocalEmbedding) {
      items.add(const _GuidanceItem(label: '启用检索范围中的本地语义检索'));
    }
    if (indexStatus.readyForIndexing && indexStatus.pendingItems.isNotEmpty) {
      items.add(
        _GuidanceItem(
          label: indexStatus.taskState.lastCompletedAt == null ? '立即构建索引' : '刷新索引',
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
  const _SearchScopeCard({required this.scope, required this.onChanged, required this.onSave});

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
              onChanged: (value) => onChanged(scope.copyWith(includeTitle: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeUsername,
              title: const Text('账号字段'),
              onChanged: (value) => onChanged(scope.copyWith(includeUsername: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includePasswordField,
              title: const Text('密码字段'),
              onChanged: (value) => onChanged(scope.copyWith(includePasswordField: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeUrl,
              title: const Text('网址字段'),
              onChanged: (value) => onChanged(scope.copyWith(includeUrl: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeSecretNote,
              title: const Text('密码附注'),
              onChanged: (value) => onChanged(scope.copyWith(includeSecretNote: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeTags,
              title: const Text('标签'),
              onChanged: (value) => onChanged(scope.copyWith(includeTags: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.includeNoteBody,
              title: const Text('笔记正文'),
              onChanged: (value) => onChanged(scope.copyWith(includeNoteBody: value)),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.allowLocalEmbedding,
              title: const Text('允许本地语义检索'),
              subtitle: const Text('当前版本仍为占位 embedding 引擎，仅先打通搜索流程。'),
              onChanged: (value) => onChanged(scope.copyWith(allowLocalEmbedding: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scope.allowExternalProviderAccess,
              title: const Text('允许外部模型访问'),
              subtitle: const Text('关闭时，后续外部 Provider 不得读取当前查询与内容。'),
              onChanged: (value) => onChanged(scope.copyWith(allowExternalProviderAccess: value)),
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

class _SearchSettingsImpactPreviewCard extends StatelessWidget {
  const _SearchSettingsImpactPreviewCard({required this.preview});

  final SearchSettingsImpactPreview preview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview.headline, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(preview.description),
            if (preview.immediateItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('立即影响', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final item in preview.immediateItems) Text('• $item'),
            ],
            if (preview.reindexItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('需要重新索引', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final item in preview.reindexItems) Text('• $item'),
            ],
            if (preview.recommendation != null) ...[
              const SizedBox(height: 12),
              Text('当前建议', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(preview.recommendation!),
            ],
          ],
        ),
      ),
    );
  }
}
