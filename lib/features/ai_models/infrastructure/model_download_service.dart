import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.averageSpeedBytesPerSecond,
  });

  final int receivedBytes;
  final int? totalBytes;
  final double? averageSpeedBytesPerSecond;
}

class ModelDownloadResult {
  const ModelDownloadResult({
    required this.localPath,
    required this.totalBytes,
  });

  final String localPath;
  final int totalBytes;
}

class ModelDownloadService {
  ModelDownloadService({required Dio dio, required AppLogger logger})
      : _dio = dio,
        _logger = logger;

  final Dio _dio;
  final AppLogger _logger;
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};

  Future<ModelDownloadResult> download({
    required String taskId,
    required String modelId,
    required String sourceUrl,
    required void Function(ModelDownloadProgress progress) onProgress,
  }) async {
    final targetFile = await _resolveTargetFile(modelId, sourceUrl);
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;
    final startedAt = DateTime.now();

    try {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      await _dio.download(
        sourceUrl,
        targetFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
          final speed = elapsed <= 0 ? null : received * 1000 / elapsed;
          onProgress(
            ModelDownloadProgress(
              receivedBytes: received,
              totalBytes: total <= 0 ? null : total,
              averageSpeedBytesPerSecond: speed,
            ),
          );
        },
      );

      final fileLength = await targetFile.length();
      _logger.info('Downloaded model $modelId to ${targetFile.path}');
      return ModelDownloadResult(localPath: targetFile.path, totalBytes: fileLength);
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  void cancel(String taskId) {
    final token = _cancelTokens.remove(taskId);
    token?.cancel('User paused download');
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
      _logger.info('Deleted local model file at $path');
    }
  }

  Future<File> _resolveTargetFile(String modelId, String sourceUrl) async {
    final appDir = await getApplicationSupportDirectory();
    final modelDir = Directory(p.join(appDir.path, 'models'));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final extension = p.extension(Uri.parse(sourceUrl).path);
    final safeExtension = extension.isEmpty ? '.bin' : extension;
    return File(p.join(modelDir.path, '$modelId$safeExtension'));
  }
}
