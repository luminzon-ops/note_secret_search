enum ModelDownloadStatus {
  idle,
  queued,
  downloading,
  paused,
  completed,
  failed,
}

class ModelDownloadTask {
  const ModelDownloadTask({
    required this.id,
    required this.modelId,
    required this.sourceId,
    required this.status,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.averageSpeed,
    required this.errorMessage,
    required this.resumable,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String modelId;
  final String sourceId;
  final ModelDownloadStatus status;
  final int? totalBytes;
  final int downloadedBytes;
  final double? averageSpeed;
  final String? errorMessage;
  final bool resumable;
  final DateTime createdAt;
  final DateTime updatedAt;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }

    return (downloadedBytes / total).clamp(0, 1);
  }

  bool get isTerminal =>
      status == ModelDownloadStatus.completed || status == ModelDownloadStatus.failed;

  ModelDownloadTask copyWith({
    String? id,
    String? modelId,
    String? sourceId,
    ModelDownloadStatus? status,
    int? totalBytes,
    bool clearTotalBytes = false,
    int? downloadedBytes,
    double? averageSpeed,
    bool clearAverageSpeed = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? resumable,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ModelDownloadTask(
      id: id ?? this.id,
      modelId: modelId ?? this.modelId,
      sourceId: sourceId ?? this.sourceId,
      status: status ?? this.status,
      totalBytes: clearTotalBytes ? null : (totalBytes ?? this.totalBytes),
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      averageSpeed: clearAverageSpeed ? null : (averageSpeed ?? this.averageSpeed),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      resumable: resumable ?? this.resumable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
