import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'model_download_service_transfer.dart';

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

class ModelDownloadService {
  ModelDownloadService({
    required Dio dio,
    required AppLogger logger,
    Future<Directory> Function()? applicationSupportDirectoryProvider,
  }) : _dio = dio,
       _logger = logger,
       _applicationSupportDirectoryProvider =
           applicationSupportDirectoryProvider ??
           getApplicationSupportDirectory;

  final Dio _dio;
  final AppLogger _logger;
  final Future<Directory> Function() _applicationSupportDirectoryProvider;
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};

  Future<ModelDownloadResult> download({
    required String taskId,
    required String modelId,
    required String sourceUrl,
    required String expectedChecksum,
    int resumeFromBytes = 0,
    required FutureOr<void> Function(ModelDownloadProgress progress) onProgress,
  }) async {
    final target = await _resolveTarget(
      modelId: modelId,
      sourceUrl: sourceUrl,
      createParent: true,
    );
    return _run(
      _Job(
        taskId: taskId,
        target: target,
        modelId: modelId,
        sourceUrl: sourceUrl,
        checksum: _normalizeChecksum(expectedChecksum),
        resumeFromBytes: resumeFromBytes,
        onProgress: onProgress,
      ),
      installOnSuccess: true,
    );
  }

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
  }) async {
    if (expectedSizeBytes <= 0) {
      throw ArgumentError.value(
        expectedSizeBytes,
        'expectedSizeBytes',
        'Signed artifact size must be positive.',
      );
    }
    final target = await resolveArtifactStagingTarget(
      modelId: modelId,
      operationId: operationId,
      artifactId: artifactId,
    );
    return _run(
      _Job(
        taskId: taskId,
        target: target,
        modelId: modelId,
        operationId: operationId,
        artifactId: artifactId,
        sourceUrl: sourceUrl,
        checksum: _normalizeChecksum(expectedChecksum),
        expectedSizeBytes: expectedSizeBytes,
        resumeFromBytes: resumeFromBytes,
        onProgress: onProgress,
      ),
      installOnSuccess: false,
    );
  }

  Future<ModelDownloadStagingTarget> resolveStagingTarget({
    required String modelId,
    required String sourceUrl,
  }) {
    return _resolveTarget(
      modelId: modelId,
      sourceUrl: sourceUrl,
      createParent: false,
    );
  }

  Future<ModelDownloadStagingTarget> resolveArtifactStagingTarget({
    required String modelId,
    required String operationId,
    required String artifactId,
  }) async {
    _validateModelId(modelId);
    _validateIdentifier(operationId, 'operationId');
    _validateIdentifier(artifactId, 'artifactId');
    final root = await _applicationSupportDirectoryProvider();
    final stagingDir = p.join(
      root.path,
      'models',
      modelId,
      '.staging',
      operationId,
    );
    final stagingPath = p.join(stagingDir, '$artifactId.part');
    return ModelDownloadStagingTarget(
      localPath: stagingPath,
      stagingPath: stagingPath,
      metadataPath: p.join(stagingDir, '$artifactId.json'),
    );
  }

  Future<ModelDownloadTarget> inspectDownloadTarget({
    required String modelId,
    required String sourceUrl,
  }) async {
    final target = await resolveStagingTarget(
      modelId: modelId,
      sourceUrl: sourceUrl,
    );
    final finalFile = File(target.localPath);
    final partialFile = File(target.stagingPath);
    final finalExists = await finalFile.exists();
    final partialExists = await partialFile.exists();
    final existing = finalExists ? finalFile : partialFile;
    return ModelDownloadTarget(
      localPath: target.localPath,
      exists: finalExists || partialExists,
      existingBytes: finalExists || partialExists ? await existing.length() : 0,
    );
  }

  Future<String> verifyChecksum({
    required String filePath,
    required String expectedChecksum,
  }) async {
    final expected = _normalizeChecksum(expectedChecksum);
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('Downloaded file is missing: $filePath');
    }
    final actual = 'sha256:${await sha256.bind(file.openRead()).first}';
    if (actual != expected) {
      throw StateError('Checksum mismatch for $filePath');
    }
    return actual;
  }

  void cancel(String taskId) {
    _cancelTokens.remove(taskId)?.cancel('User paused download');
  }

  Future<bool> fileExists(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    return File(path).exists();
  }

  Future<void> deleteLocalFile(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      _logger.info('model_file_deleted');
    }
  }
}

class _Job {
  const _Job({
    required this.taskId,
    required this.target,
    required this.modelId,
    required this.sourceUrl,
    required this.checksum,
    this.operationId,
    this.artifactId,
    this.expectedSizeBytes,
    required this.resumeFromBytes,
    required this.onProgress,
  });

  final String taskId;
  final ModelDownloadStagingTarget target;
  final String modelId;
  final String? operationId;
  final String? artifactId;
  final String sourceUrl;
  final String checksum;
  final int? expectedSizeBytes;
  final int resumeFromBytes;
  final FutureOr<void> Function(ModelDownloadProgress progress) onProgress;
}

class _Files {
  _Files(ModelDownloadStagingTarget target)
    : finalFile = File(target.localPath),
      partial = File(target.stagingPath),
      metadata = File(target.metadataPath);

  final File finalFile;
  final File partial;
  final File metadata;
}

class _Validator {
  const _Validator({this.etag, this.lastModified});

  final String? etag;
  final String? lastModified;
  bool get resumable => _strongEtag(etag) || _validHttpDate(lastModified);
  String? get ifRange => _strongEtag(etag)
      ? etag!.trim()
      : (_validHttpDate(lastModified) ? lastModified!.trim() : null);
}

class _State {
  const _State({
    this.modelId,
    this.operationId,
    this.artifactId,
    required this.sourceUrl,
    required this.checksum,
    required this.totalBytes,
    this.expectedSizeBytes,
    required this.validator,
  });

  factory _State.fromJson(Map<String, dynamic> json) {
    final sourceUrl = json['sourceUrl'];
    final checksum = json['expectedChecksum'];
    final total = json['totalBytes'];
    final expectedSize = json['expectedSizeBytes'];
    if (sourceUrl is! String ||
        checksum is! String ||
        (total != null && total is! int) ||
        (expectedSize != null && expectedSize is! int)) {
      throw const FormatException('Invalid download state.');
    }
    return _State(
      modelId: json['modelId'] as String?,
      operationId: json['operationId'] as String?,
      artifactId: json['artifactId'] as String?,
      sourceUrl: sourceUrl,
      checksum: checksum,
      totalBytes: total as int?,
      expectedSizeBytes: expectedSize as int?,
      validator: _Validator(
        etag: json['etag'] as String?,
        lastModified: json['lastModified'] as String?,
      ),
    );
  }

  final String? modelId;
  final String? operationId;
  final String? artifactId;
  final String sourceUrl;
  final String checksum;
  final int? totalBytes;
  final int? expectedSizeBytes;
  final _Validator validator;

  bool matches(_Job job) {
    final identityMatches = job.operationId == null && job.artifactId == null
        ? operationId == null && artifactId == null
        : modelId == job.modelId &&
              operationId == job.operationId &&
              artifactId == job.artifactId;
    return sourceUrl == job.sourceUrl &&
        checksum == job.checksum &&
        identityMatches &&
        expectedSizeBytes == job.expectedSizeBytes;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 2,
    'modelId': modelId,
    'operationId': operationId,
    'artifactId': artifactId,
    'sourceUrl': sourceUrl,
    'expectedChecksum': checksum,
    'totalBytes': totalBytes,
    'expectedSizeBytes': expectedSizeBytes,
    'etag': validator.etag,
    'lastModified': validator.lastModified,
  };
}

class _DownloadIntegrityException extends StateError {
  _DownloadIntegrityException(super.message);
}

bool _strongEtag(String? value) {
  final etag = value?.trim();
  return _notEmpty(etag) &&
      !etag!.toUpperCase().startsWith('W/') &&
      etag.startsWith('"') &&
      etag.endsWith('"');
}

bool _notEmpty(String? value) => value != null && value.trim().isNotEmpty;

bool _validHttpDate(String? value) {
  if (!_notEmpty(value)) {
    return false;
  }
  try {
    HttpDate.parse(value!.trim());
    return true;
  } on HttpException {
    return false;
  }
}
