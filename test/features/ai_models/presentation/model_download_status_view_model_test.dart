import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_download_status_view_model.dart';

void main() {
  test('maps zero-byte downloading task to connecting stage', () {
    final task = ModelDownloadTask(
      id: 'task-1',
      modelId: 'bge-small-zh',
      sourceId: 'source-1',
      status: ModelDownloadStatus.downloading,
      totalBytes: 10485760,
      downloadedBytes: 0,
      averageSpeed: null,
      errorMessage: null,
      resumable: true,
      createdAt: DateTime(2026, 5, 2, 10, 0, 0),
      updatedAt: DateTime(2026, 5, 2, 10, 0, 1),
    );

    final viewModel = ModelDownloadStatusViewModel.fromTask(task);

    expect(viewModel.stageLabel, '连接中');
  });

  test('maps failed task to failed stage and preserves error message', () {
    final task = ModelDownloadTask(
      id: 'task-1',
      modelId: 'bge-small-zh',
      sourceId: 'source-1',
      status: ModelDownloadStatus.failed,
      totalBytes: 10485760,
      downloadedBytes: 0,
      averageSpeed: null,
      errorMessage: 'DioException [connection timeout]',
      resumable: true,
      createdAt: DateTime(2026, 5, 2, 10, 0, 0),
      updatedAt: DateTime(2026, 5, 2, 10, 0, 1),
    );

    final viewModel = ModelDownloadStatusViewModel.fromTask(task);

    expect(viewModel.stageLabel, '失败');
    expect(viewModel.errorMessage, 'DioException [connection timeout]');
  });
}
