import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';

class ModelDownloadStatusViewModel {
  const ModelDownloadStatusViewModel({
    required this.stageLabel,
    required this.errorMessage,
  });

  final String stageLabel;
  final String? errorMessage;

  factory ModelDownloadStatusViewModel.fromTask(ModelDownloadTask task) {
    final stageLabel = switch (task.status) {
      ModelDownloadStatus.idle => '未开始',
      ModelDownloadStatus.queued => '已发起',
      ModelDownloadStatus.downloading when task.downloadedBytes == 0 => '连接中',
      ModelDownloadStatus.downloading => '下载中',
      ModelDownloadStatus.paused => '已暂停',
      ModelDownloadStatus.completed => '已完成',
      ModelDownloadStatus.failed => '失败',
    };

    return ModelDownloadStatusViewModel(
      stageLabel: stageLabel,
      errorMessage: task.errorMessage,
    );
  }
}
