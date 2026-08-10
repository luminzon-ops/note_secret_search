part of 'model_management_page.dart';

class _CatalogEntryTile extends ConsumerStatefulWidget {
  const _CatalogEntryTile({
    required this.entry,
    required this.latestTask,
    required this.installedEntry,
    required this.runtimeState,
    required this.llmRuntimeState,
    required this.allTasks,
    required this.capabilityAssessment,
    required this.activeEmbeddingModelId,
    required this.activeLlmModelId,
  });

  final ModelCatalogEntry entry;
  final ModelDownloadTask? latestTask;
  final ModelRegistryEntry? installedEntry;
  final EmbeddingEngineState? runtimeState;
  final LlmRuntimeState? llmRuntimeState;
  final List<ModelDownloadTask> allTasks;
  final ModelCapabilityAssessment? capabilityAssessment;
  final String? activeEmbeddingModelId;
  final String? activeLlmModelId;

  @override
  ConsumerState<_CatalogEntryTile> createState() => _CatalogEntryTileState();
}

class _CatalogEntryTileState extends ConsumerState<_CatalogEntryTile> {
  String? _selectedSourceId;

  @override
  void initState() {
    super.initState();
    _selectedSourceId = widget.entry.sources.isEmpty
        ? null
        : widget.entry.sources.first.id;
  }

  ModelCatalogEntry get entry => widget.entry;
  ModelDownloadTask? get latestTask => widget.latestTask;
  ModelRegistryEntry? get installedEntry => widget.installedEntry;
  EmbeddingEngineState? get runtimeState => widget.runtimeState;
  LlmRuntimeState? get llmRuntimeState => widget.llmRuntimeState;
  ModelCapabilityAssessment? get capabilityAssessment =>
      widget.capabilityAssessment;

  ModelDownloadTask? _taskForSource(String? sourceId) {
    if (sourceId == null) {
      return null;
    }
    for (final task in widget.allTasks) {
      if (task.sourceId == sourceId) {
        return task;
      }
    }
    return null;
  }

  ModelDownloadTask? get _activeTask {
    if (latestTask != null &&
        latestTask!.status == ModelDownloadStatus.downloading) {
      return latestTask;
    }
    final selected = _taskForSource(_selectedSourceId);
    if (selected != null) {
      return selected;
    }
    return latestTask;
  }

  String? get _effectiveSourceId => _activeTask?.sourceId ?? _selectedSourceId;

  ModelSourceEntry? get _effectiveSource {
    final effectiveSourceId = _effectiveSourceId;
    if (effectiveSourceId == null) {
      return _selectedSource;
    }
    for (final source in entry.sources) {
      if (source.id == effectiveSourceId) {
        return source;
      }
    }
    return _selectedSource;
  }

  ModelSourceEntry? get _selectedSource {
    for (final source in entry.sources) {
      if (source.id == _selectedSourceId) {
        return source;
      }
    }
    if (entry.sources.isEmpty) {
      return null;
    }
    return entry.sources.first;
  }

  @override
  Widget build(BuildContext context) {
    final maintenance = ref.watch(modelMaintenanceUseCaseProvider);
    final selectedSource = _selectedSource;
    final effectiveSource = _effectiveSource;
    final isInstalled = installedEntry?.isInstalled ?? false;
    final canDeleteLocalModel = installedEntry != null;
    final isDownloadSupported = isCatalogEntryDownloadSupported(entry);
    final activeTask = _activeTask;
    final isDownloading = activeTask?.status == ModelDownloadStatus.downloading;
    final canRetry =
        activeTask?.status == ModelDownloadStatus.failed || activeTask == null;
    final isActiveEmbeddingModel =
        entry.type == 'embedding' && widget.activeEmbeddingModelId == entry.id;
    final canActivateEmbedding =
        entry.type != 'embedding' ||
        ((installedEntry?.isInstalled ?? false) && runtimeState?.ready == true);
    final embeddingRuntimeState = runtimeState;
    final hasPartialBytes = (activeTask?.downloadedBytes ?? 0) > 0;
    final canResume =
        activeTask != null &&
        activeTask.resumable &&
        hasPartialBytes &&
        (activeTask.status == ModelDownloadStatus.paused ||
            activeTask.status == ModelDownloadStatus.queued ||
            activeTask.status == ModelDownloadStatus.failed);

    final primaryDownloadLabel = isInstalled
        ? '已安装'
        : activeTask == null
        ? '开始下载'
        : canResume
        ? '继续下载'
        : (activeTask.status == ModelDownloadStatus.paused ||
                  activeTask.status == ModelDownloadStatus.queued) &&
              activeTask.downloadedBytes == 0
        ? '开始下载'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.displayName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (isInstalled)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text(isActiveEmbeddingModel ? '当前语义模型' : '已安装模型'),
                ),
              ),
            Chip(label: Text(entry.type)),
          ],
        ),
        const SizedBox(height: 8),
        Text(entry.description),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('档位 ${entry.tier}')),
            Chip(label: Text('推荐 ${entry.recommendedTier}')),
            Chip(label: Text('RAM ≥ ${entry.minRamMb}MB')),
            Chip(label: Text(_formatSize(entry.sizeBytes))),
            if (capabilityAssessment?.isDefaultRecommendation == true)
              const Chip(label: Text('设备默认推荐')),
          ],
        ),
        if (capabilityAssessment != null) ...[
          const SizedBox(height: 8),
          Text(
            capabilityAssessment!.explanation,
            key: ValueKey<String>('model-capability-${entry.id}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          formatCatalogDeploymentStatus(
            installedEntry,
            runtimeState: runtimeState,
            llmRuntimeState: llmRuntimeState,
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!isDownloadSupported) ...[
          const SizedBox(height: 4),
          Text(
            formatCatalogRuntimeSupportStatus(entry),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        if (entry.type == 'multimodal_llm') ...[
          const SizedBox(height: 4),
          Text(
            formatCatalogRuntimeSupportStatus(entry),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          for (final source in entry.sources.where((source) => source.required))
            Text(
              '${source.role == 'mmproj' ? '视觉投影' : '主模型'}：${source.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
        if (entry.type == 'embedding' && embeddingRuntimeState != null) ...[
          const SizedBox(height: 4),
          Text(
            '运行时状态：${_runtimeStatusLabel(embeddingRuntimeState.status)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        _DownloadStatusCard(
          task: latestTask,
          installedEntry: installedEntry,
          sourceLabel: _sourceLabel(latestTask?.sourceId),
        ),
        const SizedBox(height: 12),
        if (entry.sources.isNotEmpty) ...[
          // Section header: "当前下载源"
          const Text('当前下载源'),
          const SizedBox(height: 4),
          // Source label on its own line (separate from the dropdown)
          Text(
            effectiveSource != null
                ? formatSourceLabelWithTrust(effectiveSource)
                : '未选择',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          // Source selector dropdown below the label
          if (entry.sources.length > 1)
            DropdownButton<String>(
              value: selectedSource?.id,
              items: [
                for (final source in entry.sources)
                  DropdownMenuItem<String>(
                    value: source.id,
                    child: Text(formatSourceLabelWithTrust(source)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedSourceId = value;
                });
              },
            ),
          if (effectiveSource != null) ...[
            if (formatEffectiveSourceTrustCaption(effectiveSource) != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  formatEffectiveSourceTrustCaption(effectiveSource)!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (shouldShowGenericTrustExplainer(entry.sources))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  formatGenericTrustExplainer(entry.sources)!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (primaryDownloadLabel != null)
              FilledButton.tonalIcon(
                onPressed:
                    selectedSource == null ||
                        isInstalled ||
                        isDownloading ||
                        !isDownloadSupported
                    ? null
                    : () => maintenance.start(
                        entry: entry,
                        source: selectedSource,
                      ),
                icon: const Icon(Icons.download_outlined),
                label: Text(primaryDownloadLabel),
              ),
            OutlinedButton.icon(
              onPressed:
                  selectedSource == null ||
                      isDownloading ||
                      isInstalled ||
                      !canRetry ||
                      canResume ||
                      !isDownloadSupported
                  ? null
                  : () =>
                        maintenance.start(entry: entry, source: selectedSource),
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('重试下载'),
            ),
            OutlinedButton.icon(
              onPressed: activeTask == null || !isDownloading
                  ? null
                  : () => maintenance.pause(
                      entry.id,
                      sourceId: activeTask.sourceId,
                    ),
              icon: const Icon(Icons.pause_outlined),
              label: const Text('暂停'),
            ),
            OutlinedButton.icon(
              onPressed: !canDeleteLocalModel
                  ? null
                  : () => maintenance.delete(entry.id),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除本地模型'),
            ),
            OutlinedButton.icon(
              onPressed:
                  !isInstalled ||
                      entry.type != 'embedding' ||
                      !canActivateEmbedding
                  ? null
                  : () => ref
                        .read(modelActivationUseCaseProvider)
                        .setEmbedding(isActiveEmbeddingModel ? null : entry.id),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(isActiveEmbeddingModel ? '取消启用' : '设为语义模型'),
            ),
            if (entry.type == 'llm' && isInstalled) ...[
              OutlinedButton.icon(
                onPressed: llmRuntimeState?.ready != true
                    ? null
                    : () => ref
                          .read(modelActivationUseCaseProvider)
                          .setLocalLlm(
                            widget.activeLlmModelId == entry.id
                                ? null
                                : entry.id,
                          ),
                icon: const Icon(Icons.smart_toy_outlined),
                label: Text(
                  widget.activeLlmModelId == entry.id ? '取消启用' : '设为当前本地LLM',
                ),
              ),
            ],
            TextButton.icon(
              onPressed: activeTask == null
                  ? null
                  : () => maintenance.markFailed(
                      entry.id,
                      sourceId: activeTask.sourceId,
                      message: '用户手动标记失败，可重新下载。',
                    ),
              icon: const Icon(Icons.error_outline),
              label: const Text('标记失败'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('推荐来源', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        for (final source in entry.sources)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(formatSourceLabelWithTrust(source)),
            subtitle: Text(source.url),
            trailing: Text(_sourceStatusLabel(source.id)),
          ),
      ],
    );
  }

  String _sourceStatusLabel(String sourceId) {
    if (latestTask == null || latestTask?.sourceId != sourceId) {
      return '未下载';
    }
    return _statusLabel(latestTask!.status);
  }

  String? _sourceLabel(String? sourceId) {
    if (sourceId == null) {
      return null;
    }
    for (final source in entry.sources) {
      if (source.id == sourceId) {
        return formatSourceLabelWithTrust(source);
      }
    }
    return null;
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) {
      return '未知大小';
    }

    final sizeMb = bytes / (1024 * 1024);
    if (sizeMb >= 1024) {
      return '${(sizeMb / 1024).toStringAsFixed(1)} GB';
    }
    return '${sizeMb.toStringAsFixed(0)} MB';
  }

  String _statusLabel(ModelDownloadStatus status) {
    switch (status) {
      case ModelDownloadStatus.idle:
        return '未开始';
      case ModelDownloadStatus.queued:
        return '队列中';
      case ModelDownloadStatus.downloading:
        return '下载中';
      case ModelDownloadStatus.paused:
        return '已暂停';
      case ModelDownloadStatus.completed:
        return '已完成';
      case ModelDownloadStatus.failed:
        return '失败';
    }
  }
}

String _runtimeStatusLabel(EmbeddingRuntimeStatus status) {
  switch (status) {
    case EmbeddingRuntimeStatus.notInstalled:
      return '未安装';
    case EmbeddingRuntimeStatus.missing:
      return '文件缺失';
    case EmbeddingRuntimeStatus.corrupted:
      return '文件损坏';
    case EmbeddingRuntimeStatus.installedUnverified:
      return '待校验';
    case EmbeddingRuntimeStatus.ready:
      return '已就绪';
    case EmbeddingRuntimeStatus.degraded:
      return '运行时异常';
  }
}
