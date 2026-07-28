import 'dart:async';

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.averageSpeedBytesPerSecond,
    this.etag,
    this.lastModified,
    this.resumable,
    this.restarted = false,
  });

  final int receivedBytes;
  final int? totalBytes;
  final double? averageSpeedBytesPerSecond;
  final String? etag;
  final String? lastModified;
  final bool? resumable;
  final bool restarted;
}

class ModelDownloadStagingTarget {
  const ModelDownloadStagingTarget({
    required this.localPath,
    required this.stagingPath,
    required this.metadataPath,
  });

  final String localPath;
  final String stagingPath;
  final String metadataPath;
}

class ModelDownloadResult {
  const ModelDownloadResult({
    required this.localPath,
    required this.totalBytes,
    required this.verifiedChecksum,
    this.resumed = false,
    this.fellBackToRestart = false,
    this.resumable = true,
    this.etag,
    this.lastModified,
  });

  final String localPath;
  final int totalBytes;
  final String verifiedChecksum;
  final bool resumed;
  final bool fellBackToRestart;
  final bool resumable;
  final String? etag;
  final String? lastModified;
}

class ModelDownloadTarget {
  const ModelDownloadTarget({
    required this.localPath,
    required this.exists,
    required this.existingBytes,
  });

  final String localPath;
  final bool exists;
  final int existingBytes;
}

abstract interface class ModelDownloadGateway {
  Future<ModelDownloadResult> download({
    required String taskId,
    required String modelId,
    required String sourceUrl,
    required String expectedChecksum,
    int resumeFromBytes = 0,
    required FutureOr<void> Function(ModelDownloadProgress progress) onProgress,
  });

  Future<ModelDownloadResult> stageArtifact({
    required String taskId,
    required String modelId,
    required String operationId,
    required String artifactId,
    required String sourceUrl,
    required String expectedChecksum,
    required int expectedSizeBytes,
    int resumeFromBytes = 0,
    required FutureOr<void> Function(ModelDownloadProgress progress) onProgress,
  });

  Future<ModelDownloadStagingTarget> resolveStagingTarget({
    required String modelId,
    required String sourceUrl,
  });

  Future<ModelDownloadStagingTarget> resolveArtifactStagingTarget({
    required String modelId,
    required String operationId,
    required String artifactId,
  });

  Future<ModelDownloadTarget> inspectDownloadTarget({
    required String modelId,
    required String sourceUrl,
  });

  Future<String> verifyChecksum({
    required String filePath,
    required String expectedChecksum,
  });

  void cancel(String taskId);

  Future<bool> fileExists(String? path);

  Future<int?> fileLength(String? path);

  Future<void> deleteLocalFile(String? path);

  bool isFailoverEligible(Object error);

  bool isCancellation(Object error);

  bool isResumableValidator({String? etag, String? lastModified});
}
