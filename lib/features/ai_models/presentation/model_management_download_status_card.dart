part of 'model_management_page.dart';

class _DownloadStatusCard extends StatelessWidget {
  const _DownloadStatusCard({
    required this.task,
    this.installedEntry,
    this.sourceLabel,
  });

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

    final statusViewModel = ModelDownloadStatusViewModel.fromTask(task!);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header: "下载状态"
            const Text('下载状态'),
            const SizedBox(height: 8),
            // Compact staged status label
            Row(
              children: [
                const Icon(Icons.download_for_offline_outlined),
                const SizedBox(width: 8),
                Text(statusViewModel.stageLabel),
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
            Text(
              '已下载 ${_formatBytes(task!.downloadedBytes)} / ${_formatBytes(task!.totalBytes ?? 0)}',
            ),
            if (task!.errorMessage != null &&
                task!.errorMessage!.isNotEmpty) ...[
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
