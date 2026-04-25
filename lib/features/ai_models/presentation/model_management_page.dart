import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_presentation_formatter.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';

class ModelManagementPage extends ConsumerWidget {
  const ModelManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(modelCatalogEntriesProvider);
    final taskAsync = ref.watch(modelDownloadTasksProvider);
    final registryAsync = ref.watch(modelRegistryEntriesProvider);
    final runtimeStatesAsync = ref.watch(embeddingRuntimeStatesProvider);
    final selectionAsync = ref.watch(activeModelSelectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('模型')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _DeviceTierCard(),
          const SizedBox(height: 16),
          const _ModelDownloadNoticeCard(),
          const SizedBox(height: 16),
          registryAsync.when(
            data: (entries) {
              final runtimeStates = runtimeStatesAsync.valueOrNull ?? const <String, EmbeddingEngineState>{};
              return selectionAsync.when(
                data: (selection) => _InstalledModelsCard(
                  entries: entries,
                  runtimeStates: runtimeStates,
                  activeEmbeddingModelId: selection.activeEmbeddingModelId,
                ),
                loading: () => _InstalledModelsCard(
                  entries: entries,
                  runtimeStates: runtimeStates,
                  activeEmbeddingModelId: null,
                ),
                error: (error, stackTrace) => _InstalledModelsCard(
                  entries: entries,
                  runtimeStates: runtimeStates,
                  activeEmbeddingModelId: null,
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('已安装模型读取失败：$error'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          catalogAsync.when(
            data: (entries) => taskAsync.when(
              data: (tasks) => _CatalogSection(entries: entries, tasks: tasks),
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, stackTrace) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('下载任务读取失败：$error'),
                ),
              ),
            ),
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, stackTrace) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('模型目录读取失败：$error'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTierCard extends StatelessWidget {
  const _DeviceTierCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设备能力评级'),
            SizedBox(height: 8),
            Text('当前为 MVP 保守实现：先展示模型目录，再接设备探测、下载状态机与安装校验。'),
          ],
        ),
      ),
    );
  }
}

class _ModelDownloadNoticeCard extends StatelessWidget {
  const _ModelDownloadNoticeCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('模型下载与本地部署说明'),
            SizedBox(height: 8),
            Text('当前已接入基础真实下载：文件会下载到应用私有目录，并在成功后登记本地路径。MVP 阶段仍未完成断点续传、校验和校验、安装探测与完整恢复逻辑。'),
          ],
        ),
      ),
    );
  }
}

class _InstalledModelsCard extends StatelessWidget {
  const _InstalledModelsCard({
    required this.entries,
    required this.runtimeStates,
    required this.activeEmbeddingModelId,
  });

  final List<ModelRegistryEntry> entries;
  final Map<String, EmbeddingEngineState> runtimeStates;
  final String? activeEmbeddingModelId;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('当前尚未安装本地模型。'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本地已安装模型', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final entry in entries)
              Builder(
                builder: (context) {
                  final runtimeState = runtimeStates[entry.id];
                  final isRuntimeReady = entry.type != 'embedding' || runtimeState?.ready == true;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isRuntimeReady && entry.isInstalled
                          ? Icons.inventory_2_outlined
                          : Icons.warning_amber_outlined,
                    ),
                    title: Text(entry.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatModelCapabilitySummary(entry)),
                        const SizedBox(height: 2),
                        Text(
                          formatInstalledModelDeploymentStatus(
                            entry,
                            runtimeState: runtimeState,
                          ),
                        ),
                        if (entry.type == 'embedding' && runtimeState != null) ...[
                          const SizedBox(height: 2),
                          Text('运行时状态：${_runtimeStatusLabel(runtimeState.status)}'),
                        ],
                        if (entry.localPath != null && entry.localPath!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(entry.localPath!),
                        ],
                      ],
                    ),
                    trailing: Text(
                      activeEmbeddingModelId == entry.id
                          ? '当前语义模型'
                          : (isRuntimeReady && entry.isInstalled ? '已安装模型' : '本地记录失效'),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogSection extends ConsumerWidget {
  const _CatalogSection({required this.entries, required this.tasks});

  final List<ModelCatalogEntry> entries;
  final List<ModelDownloadTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedAsync = ref.watch(modelRegistryEntriesProvider);
    final runtimeStatesAsync = ref.watch(embeddingRuntimeStatesProvider);

    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂无可用模型目录。'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('可下载模型目录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            installedAsync.when(
              data: (installedEntries) {
                final runtimeStates = runtimeStatesAsync.valueOrNull ?? const <String, EmbeddingEngineState>{};
                return Column(
                  children: [
                    for (final entry in entries) ...[
                      _CatalogEntryTile(
                        entry: entry,
                        latestTask: _latestTaskFor(entry.id),
                        installedEntry: _installedFor(installedEntries, entry.id),
                        runtimeState: runtimeStates[entry.id],
                      ),
                      if (entry != entries.last) const Divider(height: 24),
                    ],
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('安装状态读取失败：$error'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ModelDownloadTask? _latestTaskFor(String modelId) {
    for (final task in tasks) {
      if (task.modelId == modelId) {
        return task;
      }
    }
    return null;
  }

  ModelRegistryEntry? _installedFor(List<ModelRegistryEntry> entries, String modelId) {
    for (final entry in entries) {
      if (entry.id == modelId) {
        return entry;
      }
    }
    return null;
  }
}

class _CatalogEntryTile extends ConsumerWidget {
  const _CatalogEntryTile({
    required this.entry,
    required this.latestTask,
    required this.installedEntry,
    required this.runtimeState,
  });

  final ModelCatalogEntry entry;
  final ModelDownloadTask? latestTask;
  final ModelRegistryEntry? installedEntry;
  final EmbeddingEngineState? runtimeState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(modelDownloadControllerProvider);
    final primarySource = entry.sources.isEmpty ? null : entry.sources.first;
    final selectionAsync = ref.watch(activeModelSelectionProvider);
    final isInstalled = installedEntry?.isInstalled ?? false;
    final isDownloading = latestTask?.status == ModelDownloadStatus.downloading;
    final canRetry = latestTask?.status == ModelDownloadStatus.failed || latestTask == null;
    final activeEmbeddingModelId = selectionAsync.valueOrNull?.activeEmbeddingModelId;
    final isActiveEmbeddingModel = entry.type == 'embedding' && activeEmbeddingModelId == entry.id;
    final canActivateEmbedding =
        entry.type != 'embedding' || ((installedEntry?.isInstalled ?? false) && runtimeState?.ready == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(entry.displayName, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (isInstalled)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(label: Text(isActiveEmbeddingModel ? '当前语义模型' : '已安装模型')),
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
          ],
        ),
        const SizedBox(height: 8),
        Text(
          formatCatalogDeploymentStatus(installedEntry, runtimeState: runtimeState),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (entry.type == 'embedding' && runtimeState != null) ...[
          const SizedBox(height: 4),
          Text(
            '运行时状态：${_runtimeStatusLabel(runtimeState!.status)}',
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: primarySource == null || isInstalled || isDownloading
                  ? null
                  : () => controller.startDownload(
                        entry: entry,
                        source: primarySource,
                      ),
              icon: const Icon(Icons.download_outlined),
              label: Text(isInstalled ? '已安装' : '开始下载'),
            ),
            OutlinedButton.icon(
              onPressed: primarySource == null || isDownloading || isInstalled || !canRetry
                  ? null
                  : () => controller.startDownload(
                        entry: entry,
                        source: primarySource,
                      ),
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('重试下载'),
            ),
            OutlinedButton.icon(
              onPressed: latestTask == null || !isDownloading ? null : () => controller.pause(entry.id),
              icon: const Icon(Icons.pause_outlined),
              label: const Text('暂停'),
            ),
            OutlinedButton.icon(
              onPressed: !isInstalled
                  ? null
                  : () => controller.deleteInstalledModel(entry.id),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除本地模型'),
            ),
            OutlinedButton.icon(
              onPressed: !isInstalled || entry.type != 'embedding'
                      || !canActivateEmbedding
                   ? null
                   : () => ref
                       .read(activeModelSelectionControllerProvider)
                       .setActiveEmbeddingModel(isActiveEmbeddingModel ? null : entry.id),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(isActiveEmbeddingModel ? '取消启用' : '设为语义模型'),
            ),
            TextButton.icon(
              onPressed: latestTask == null
                  ? null
                  : () => controller.markFailed(entry.id, '用户手动标记失败，可重新下载。'),
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
            title: Text(source.label),
            subtitle: Text(source.url),
            trailing: Text(_sourceStatusLabel(source.id)),
          ),
      ],
    );
  }

  String _sourceStatusLabel(String sourceId) {
    if (latestTask == null || latestTask!.sourceId != sourceId) {
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
        return source.label;
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
    case EmbeddingRuntimeStatus.installedUnverified:
      return '待校验';
    case EmbeddingRuntimeStatus.ready:
      return '已就绪';
    case EmbeddingRuntimeStatus.degraded:
      return '运行时异常';
  }
}

class _DownloadStatusCard extends StatelessWidget {
  const _DownloadStatusCard({required this.task, this.installedEntry, this.sourceLabel});

  final ModelDownloadTask? task;
  final ModelRegistryEntry? installedEntry;
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    if (installedEntry?.isInstalled ?? false) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: const Icon(Icons.verified_outlined),
          title: const Text('本地部署已就绪'),
          subtitle: Text(installedEntry?.localPath ?? '路径未知'),
        ),
      );
    }

    if (task == null) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.downloading_outlined),
        title: Text('下载任务未开始'),
        subtitle: Text('当前只建立下载状态机骨架，后续会接入真实下载器。'),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_for_offline_outlined),
                const SizedBox(width: 8),
                Text('任务状态：${_statusLabel(task!.status)}'),
              ],
            ),
            const SizedBox(height: 8),
            Text('任务说明：${_statusDescription(task!.status)}'),
            const SizedBox(height: 8),
            if (task!.progress != null)
              LinearProgressIndicator(value: task!.progress)
            else
              const LinearProgressIndicator(),
            const SizedBox(height: 8),
            if (task!.averageSpeed != null) ...[
              Text('下载速度：${_formatBytesPerSecond(task!.averageSpeed!)}'),
              const SizedBox(height: 4),
            ],
            Text('断点续传：${task!.resumable ? '支持' : '当前下载源不支持'}'),
            const SizedBox(height: 8),
            if (sourceLabel != null && sourceLabel!.isNotEmpty) ...[
              Text('当前来源：$sourceLabel'),
              const SizedBox(height: 4),
            ],
            Text('任务创建：${_formatDateTime(task!.createdAt)}'),
            const SizedBox(height: 4),
            Text('最近更新：${_formatDateTime(task!.updatedAt)}'),
            const SizedBox(height: 8),
            if (task!.progress != null) ...[
              Text('下载进度：${(task!.progress! * 100).round()}%'),
              const SizedBox(height: 4),
            ],
            Text('已下载 ${_formatBytes(task!.downloadedBytes)} / ${_formatBytes(task!.totalBytes ?? 0)}'),
            if (task!.errorMessage != null && task!.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task!.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
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

  String _statusDescription(ModelDownloadStatus status) {
    switch (status) {
      case ModelDownloadStatus.idle:
        return '下载任务尚未开始，可直接发起下载。';
      case ModelDownloadStatus.queued:
        return '已加入下载队列，等待开始下载。';
      case ModelDownloadStatus.downloading:
        return '正在下载模型文件，请保持应用可继续运行。';
      case ModelDownloadStatus.paused:
        return '下载已暂停，可稍后继续或重新开始。';
      case ModelDownloadStatus.completed:
        return '下载已完成，等待进入本地部署或可用状态。';
      case ModelDownloadStatus.failed:
        return '下载失败，可检查网络或重新发起下载。';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 MB';
    }

    final sizeMb = bytes / (1024 * 1024);
    if (sizeMb >= 1024) {
      return '${(sizeMb / 1024).toStringAsFixed(1)} GB';
    }
    return '${sizeMb.toStringAsFixed(0)} MB';
  }

  String _formatBytesPerSecond(double bytesPerSecond) {
    if (bytesPerSecond <= 0) {
      return '0 MB/s';
    }

    final sizeMb = bytesPerSecond / (1024 * 1024);
    if (sizeMb >= 1024) {
      return '${(sizeMb / 1024).toStringAsFixed(1)} GB/s';
    }
    return '${sizeMb.toStringAsFixed(1)} MB/s';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }
}
