enum ModelDownloadStatus {
  idle,
  queued,
  downloading,
  paused,
  completed,
  failed,
}

enum ModelDownloadPhase {
  legacy,
  queued,
  probing,
  downloading,
  paused,
  verifying,
  staged,
  runtimeValidating,
  releasingSessions,
  installing,
  committing,
  completed,
  retryableFailed,
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
    this.operationId,
    this.attemptGeneration = 0,
    this.releaseId,
    this.artifactId,
    this.sourceUrl,
    this.stagingPath,
    this.expectedChecksum,
    this.expectedSizeBytes,
    this.etag,
    this.lastModified,
    this.phase = ModelDownloadPhase.legacy,
    this.retryReason,
    this.receivedBytes,
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
  final String? operationId;
  final int attemptGeneration;
  final String? releaseId;
  final String? artifactId;
  final String? sourceUrl;
  final String? stagingPath;
  final String? expectedChecksum;
  final int? expectedSizeBytes;
  final String? etag;
  final String? lastModified;
  final ModelDownloadPhase phase;
  final String? retryReason;
  final int? receivedBytes;

  int get effectiveReceivedBytes => receivedBytes ?? downloadedBytes;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }

    return (downloadedBytes / total).clamp(0, 1);
  }

  bool get isTerminal =>
      status == ModelDownloadStatus.completed ||
      status == ModelDownloadStatus.failed;

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
    String? operationId,
    bool clearOperationId = false,
    int? attemptGeneration,
    String? releaseId,
    bool clearReleaseId = false,
    String? artifactId,
    bool clearArtifactId = false,
    String? sourceUrl,
    bool clearSourceUrl = false,
    String? stagingPath,
    bool clearStagingPath = false,
    String? expectedChecksum,
    bool clearExpectedChecksum = false,
    int? expectedSizeBytes,
    bool clearExpectedSizeBytes = false,
    String? etag,
    bool clearEtag = false,
    String? lastModified,
    bool clearLastModified = false,
    ModelDownloadPhase? phase,
    String? retryReason,
    bool clearRetryReason = false,
    int? receivedBytes,
    bool clearReceivedBytes = false,
  }) {
    return ModelDownloadTask(
      id: id ?? this.id,
      modelId: modelId ?? this.modelId,
      sourceId: sourceId ?? this.sourceId,
      status: status ?? this.status,
      totalBytes: clearTotalBytes ? null : (totalBytes ?? this.totalBytes),
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      averageSpeed: clearAverageSpeed
          ? null
          : (averageSpeed ?? this.averageSpeed),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      resumable: resumable ?? this.resumable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      operationId: clearOperationId ? null : (operationId ?? this.operationId),
      attemptGeneration: attemptGeneration ?? this.attemptGeneration,
      releaseId: clearReleaseId ? null : (releaseId ?? this.releaseId),
      artifactId: clearArtifactId ? null : (artifactId ?? this.artifactId),
      sourceUrl: clearSourceUrl ? null : (sourceUrl ?? this.sourceUrl),
      stagingPath: clearStagingPath ? null : (stagingPath ?? this.stagingPath),
      expectedChecksum: clearExpectedChecksum
          ? null
          : (expectedChecksum ?? this.expectedChecksum),
      expectedSizeBytes: clearExpectedSizeBytes
          ? null
          : (expectedSizeBytes ?? this.expectedSizeBytes),
      etag: clearEtag ? null : (etag ?? this.etag),
      lastModified: clearLastModified
          ? null
          : (lastModified ?? this.lastModified),
      phase: phase ?? this.phase,
      retryReason: clearRetryReason ? null : (retryReason ?? this.retryReason),
      receivedBytes: clearReceivedBytes
          ? null
          : (receivedBytes ?? this.receivedBytes),
    );
  }
}
