import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

class ModelManagementPage extends ConsumerWidget {
  const ModelManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(modelCatalogEntriesProvider);
    final taskAsync = ref.watch(modelDownloadTasksProvider);
    final registryAsync = ref.watch(modelRegistryEntriesProvider);
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
            data: (entries) => selectionAsync.when(
              data: (selection) => _InstalledModelsCard(
                entries: entries,
                activeEmbeddingModelId: selection.activeEmbeddingModelId,
              ),
              loading: () => _InstalledModelsCard(entries: entries, activeEmbeddingModelId: null),
              error: (error, stackTrace) => _InstalledModelsCard(
                entries: entries,
                activeEmbeddingModelId: null,
              ),
            ),
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
            Text('设备评级'),
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
            Text('模型下载与部署说明'),
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
    required this.activeEmbeddingModelId,
  });

  final List<ModelRegistryEntry> entries;
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
            Text('已安装模型', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final entry in entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entry.isInstalled ? Icons.inventory_2_outlined : Icons.warning_amber_outlined,
                ),
                title: Text(entry.name),
                subtitle: Text(entry.localPath ?? '路径未知'),
                trailing: Text(
                  activeEmbeddingModelId == entry.id
                      ? '当前语义模型'
                      : (entry.isInstalled ? '已安装' : '记录失效'),
                ),
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
            Text('内置模型目录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            installedAsync.when(
              data: (installedEntries) => Column(
                children: [
                  for (final entry in entries) ...[
                    _CatalogEntryTile(
                      entry: entry,
                      latestTask: _latestTaskFor(entry.id),
                      installedEntry: _installedFor(installedEntries, entry.id),
                    ),
                    if (entry != entries.last) const Divider(height: 24),
                  ],
                ],
              ),
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
  });

  final ModelCatalogEntry entry;
  final ModelDownloadTask? latestTask;
  final ModelRegistryEntry? installedEntry;

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
                child: Chip(label: Text(isActiveEmbeddingModel ? '已启用' : '已安装')),
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
        const SizedBox(height: 12),
        _DownloadStatusCard(task: latestTask, installedEntry: installedEntry),
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

class _DownloadStatusCard extends StatelessWidget {
  const _DownloadStatusCard({required this.task, this.installedEntry});

  final ModelDownloadTask? task;
  final ModelRegistryEntry? installedEntry;

  @override
  Widget build(BuildContext context) {
    if (installedEntry?.isInstalled ?? false) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: const Icon(Icons.verified_outlined),
          title: const Text('本地模型已安装'),
          subtitle: Text(installedEntry?.localPath ?? '路径未知'),
        ),
      );
    }

    if (task == null) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.downloading_outlined),
        title: Text('尚未创建下载任务'),
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
            if (task!.progress != null)
              LinearProgressIndicator(value: task!.progress)
            else
              const LinearProgressIndicator(),
            const SizedBox(height: 8),
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
}
