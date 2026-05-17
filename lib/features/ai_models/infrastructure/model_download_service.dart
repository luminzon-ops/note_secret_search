import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
    required this.verifiedChecksum,
    this.resumed = false,
    this.fellBackToRestart = false,
    this.resumable = true,
  });

  final String localPath;
  final int totalBytes;
  final String verifiedChecksum;
  final bool resumed;
  final bool fellBackToRestart;
  final bool resumable;
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
  })
      : _dio = dio,
        _logger = logger,
        _applicationSupportDirectoryProvider =
            applicationSupportDirectoryProvider ?? getApplicationSupportDirectory;

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
    final target = await inspectDownloadTarget(
      modelId: modelId,
      sourceUrl: sourceUrl,
    );
    final targetFile = File(target.localPath);
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;
    final startedAt = DateTime.now();
    final effectiveResumeFromBytes =
        target.exists ? (resumeFromBytes <= target.existingBytes ? resumeFromBytes : target.existingBytes) : 0;
    var resumed = false;
    var fellBackToRestart = false;
    var resumable = effectiveResumeFromBytes > 0;

    try {
      if (effectiveResumeFromBytes > 0) {
        final response = await _streamDownload(
          sourceUrl: sourceUrl,
          cancelToken: cancelToken,
          rangeStart: effectiveResumeFromBytes,
        );

        final statusCode = response.statusCode ?? 200;
        if (statusCode == HttpStatus.partialContent) {
          resumed = true;
          await _writeResponseBody(
            targetFile: targetFile,
            body: response.data,
            append: true,
            existingBytes: effectiveResumeFromBytes,
            startedAt: startedAt,
            onProgress: onProgress,
          );
        } else {
          resumed = false;
          resumable = false;
          fellBackToRestart = true;
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          final fullResponse = await _streamDownload(
            sourceUrl: sourceUrl,
            cancelToken: cancelToken,
          );
          await _writeResponseBody(
            targetFile: targetFile,
            body: fullResponse.data,
            append: false,
            existingBytes: 0,
            startedAt: startedAt,
            onProgress: onProgress,
          );
        }
      } else {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        final response = await _streamDownload(
          sourceUrl: sourceUrl,
          cancelToken: cancelToken,
        );
        await _writeResponseBody(
          targetFile: targetFile,
          body: response.data,
          append: false,
          existingBytes: 0,
          startedAt: startedAt,
          onProgress: onProgress,
        );
      }

      final fileLength = await targetFile.length();
      final verifiedChecksum = await verifyChecksum(
        filePath: targetFile.path,
        expectedChecksum: expectedChecksum,
      );
      _logger.info('Downloaded model $modelId to ${targetFile.path}');
      return ModelDownloadResult(
        localPath: targetFile.path,
        totalBytes: fileLength,
        verifiedChecksum: verifiedChecksum,
        resumed: resumed,
        fellBackToRestart: fellBackToRestart,
        resumable: resumable,
      );
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  Future<ModelDownloadTarget> inspectDownloadTarget({
    required String modelId,
    required String sourceUrl,
  }) async {
    final targetFile = await _resolveTargetFile(modelId, sourceUrl);
    final exists = await targetFile.exists();
    final existingBytes = exists ? await targetFile.length() : 0;
    return ModelDownloadTarget(
      localPath: targetFile.path,
      exists: exists,
      existingBytes: existingBytes,
    );
  }

  Future<String> verifyChecksum({
    required String filePath,
    required String expectedChecksum,
  }) async {
    final normalizedExpected = expectedChecksum.trim().toLowerCase();
    if (normalizedExpected.isEmpty) {
      throw StateError('Missing checksum for $filePath');
    }
    if (!normalizedExpected.startsWith('sha256:')) {
      throw StateError('Unsupported checksum format: $expectedChecksum');
    }

    final digest = await sha256.bind(File(filePath).openRead()).first;
    final verifiedChecksum = 'sha256:${digest.toString()}';
    if (verifiedChecksum != normalizedExpected) {
      throw StateError('Checksum mismatch for $filePath');
    }

    return verifiedChecksum;
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

  Future<Response<ResponseBody>> _streamDownload({
    required String sourceUrl,
    required CancelToken cancelToken,
    int? rangeStart,
  }) {
    return _dio.get<ResponseBody>(
      sourceUrl,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: rangeStart == null ? null : <String, Object>{HttpHeaders.rangeHeader: 'bytes=$rangeStart-'},
      ),
    );
  }

  Future<void> _writeResponseBody({
    required File targetFile,
    required ResponseBody? body,
    required bool append,
    required int existingBytes,
    required DateTime startedAt,
    required FutureOr<void> Function(ModelDownloadProgress progress) onProgress,
  }) async {
    if (body == null) {
      throw StateError('Download response body is empty.');
    }

    final totalBodyBytes = body.contentLength >= 0 ? body.contentLength : null;
    final totalBytes = totalBodyBytes == null ? null : totalBodyBytes + existingBytes;
    var receivedBytes = existingBytes;
    final sink = targetFile.openWrite(mode: append ? FileMode.append : FileMode.writeOnly);

    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
        final speed = elapsed <= 0 ? null : receivedBytes * 1000 / elapsed;
        await Future.sync(() => onProgress(
          ModelDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            averageSpeedBytesPerSecond: speed,
          ),
        ));
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<File> _resolveTargetFile(String modelId, String sourceUrl) async {
    final appDir = await _applicationSupportDirectoryProvider();
    final modelDir = Directory(p.join(appDir.path, 'models', modelId));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final uri = Uri.parse(sourceUrl);
    final rawFileName = p.basename(uri.path);
    final safeFileName = _sanitizeFileName(rawFileName.isEmpty ? '$modelId.bin' : rawFileName);
    return File(p.join(modelDir.path, safeFileName));
  }

  String _sanitizeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? 'artifact.bin' : sanitized;
  }
}
