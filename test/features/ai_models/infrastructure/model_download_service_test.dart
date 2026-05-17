import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';

void main() {
  String checksumFor(List<int> bytes) {
    return 'sha256:${sha256.convert(bytes).toString()}';
  }

  Future<HttpServer> startServer(
    Future<void> Function(HttpRequest request) handler,
  ) {
    return HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
      server.listen(handler);
      return server;
    });
  }

  test('inspectDownloadTarget returns existing partial byte count for a model file', () async {
    final tempDir = await Directory.systemTemp.createTemp('model-download-service');
    addTearDown(() => tempDir.delete(recursive: true));

    final service = ModelDownloadService(
      dio: Dio(),
      logger: const AppLogger(),
      applicationSupportDirectoryProvider: () async => tempDir,
    );

    final file = File('${tempDir.path}/models/embed-1/embed-1.onnx');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(128, 1));

    final target = await service.inspectDownloadTarget(
      modelId: 'embed-1',
      sourceUrl: 'https://example.com/embed-1.onnx',
    );

    expect(
      target.localPath.replaceAll('\\', '/'),
      file.path.replaceAll('\\', '/'),
    );
    expect(target.existingBytes, 128);
    expect(target.exists, isTrue);
  });

  test('inspectDownloadTarget uses source-specific filenames for multimodal artifacts', () async {
    final tempDir = await Directory.systemTemp.createTemp('model-download-service');
    addTearDown(() => tempDir.delete(recursive: true));

    final service = ModelDownloadService(
      dio: Dio(),
      logger: const AppLogger(),
      applicationSupportDirectoryProvider: () async => tempDir,
    );

    final modelTarget = await service.inspectDownloadTarget(
      modelId: 'minicpm_v_4_6_q4_k_m',
      sourceUrl: 'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/MiniCPM-V-4_6-Q4_K_M.gguf',
    );
    final mmprojTarget = await service.inspectDownloadTarget(
      modelId: 'minicpm_v_4_6_q4_k_m',
      sourceUrl: 'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/mmproj-model-f16.gguf',
    );

    expect(modelTarget.localPath, isNot(mmprojTarget.localPath));
    expect(modelTarget.localPath.replaceAll('\\', '/'), contains('MiniCPM-V-4_6-Q4_K_M.gguf'));
    expect(mmprojTarget.localPath.replaceAll('\\', '/'), contains('mmproj-model-f16.gguf'));
  });

  test('download appends bytes when the source supports HTTP Range resume', () async {
    final tempDir = await Directory.systemTemp.createTemp('model-download-service');
    addTearDown(() => tempDir.delete(recursive: true));

    final finalBytes = <int>[1, 2, 3, 4, 5, 6, 7, 8];
    final server = await startServer((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=4-');
      request.response.statusCode = HttpStatus.partialContent;
      request.response.contentLength = 4;
      request.response.add(<int>[5, 6, 7, 8]);
      await request.response.close();
    });
    addTearDown(server.close);

    final service = ModelDownloadService(
      dio: Dio(),
      logger: const AppLogger(),
      applicationSupportDirectoryProvider: () async => tempDir,
    );

    final file = File('${tempDir.path}/models/embed-1/embed-1.onnx');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[1, 2, 3, 4]);

    final result = await service.download(
      taskId: 'task-1',
      modelId: 'embed-1',
      sourceUrl: 'http://${server.address.host}:${server.port}/embed-1.onnx',
      expectedChecksum: checksumFor(finalBytes),
      resumeFromBytes: 4,
      onProgress: (_) {},
    );

    expect(await file.readAsBytes(), finalBytes);
    expect(result.resumed, isTrue);
    expect(result.fellBackToRestart, isFalse);
    expect(result.totalBytes, 8);
  });

  test('download falls back to a clean full restart when Range is ignored', () async {
    final tempDir = await Directory.systemTemp.createTemp('model-download-service');
    addTearDown(() => tempDir.delete(recursive: true));

    final fullBytes = <int>[9, 9, 9, 9];
    var requestCount = 0;
    final server = await startServer((request) async {
      requestCount++;
      if (requestCount == 1) {
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=4-');
      } else {
        expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = fullBytes.length;
      request.response.add(fullBytes);
      await request.response.close();
    });
    addTearDown(server.close);

    final service = ModelDownloadService(
      dio: Dio(),
      logger: const AppLogger(),
      applicationSupportDirectoryProvider: () async => tempDir,
    );

    final file = File('${tempDir.path}/models/embed-1/embed-1.onnx');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[1, 2, 3, 4]);

    final result = await service.download(
      taskId: 'task-1',
      modelId: 'embed-1',
      sourceUrl: 'http://${server.address.host}:${server.port}/embed-1.onnx',
      expectedChecksum: checksumFor(fullBytes),
      resumeFromBytes: 4,
      onProgress: (_) {},
    );

    expect(await file.readAsBytes(), fullBytes);
    expect(result.resumed, isFalse);
    expect(result.fellBackToRestart, isTrue);
    expect(result.totalBytes, 4);
    expect(result.resumable, isFalse);
    expect(requestCount, 2);
  });

  test('download awaits async progress callbacks before completing', () async {
    final tempDir = await Directory.systemTemp.createTemp('model-download-service');
    addTearDown(() => tempDir.delete(recursive: true));

    final bytes = <int>[1, 2, 3, 4];
    final server = await startServer((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    addTearDown(server.close);

    final service = ModelDownloadService(
      dio: Dio(),
      logger: const AppLogger(),
      applicationSupportDirectoryProvider: () async => tempDir,
    );

    var progressCompleted = false;
    final result = await service.download(
      taskId: 'task-async-progress',
      modelId: 'embed-1',
      sourceUrl: 'http://${server.address.host}:${server.port}/embed-1.onnx',
      expectedChecksum: checksumFor(bytes),
      onProgress: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        progressCompleted = true;
      },
    );

    expect(progressCompleted, isTrue);
    expect(result.totalBytes, bytes.length);
  });
}
