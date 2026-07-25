import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';

import 'model_download_http_fixture.dart';

void main() {
  test('artifact progress exposes the persisted resume validator', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'model-download-progress',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final bytes = <int>[1, 2, 3, 4];
    final fixture =
        await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(
            statusCode: HttpStatus.ok,
            body: bytes,
            etag: '"artifact-v1"',
          ),
        ]);
    addTearDown(fixture.close);
    final service = ModelDownloadService(
      dio: Dio(),
      logger: const AppLogger(),
      applicationSupportDirectoryProvider: () async => tempDir,
    );
    final progress = <ModelDownloadProgress>[];

    await service.stageArtifact(
      taskId: 'task-progress',
      modelId: 'model-1',
      operationId: 'operation-1',
      artifactId: 'model',
      sourceUrl: fixture.uri().toString(),
      expectedChecksum: 'sha256:${sha256.convert(bytes)}',
      expectedSizeBytes: bytes.length,
      onProgress: progress.add,
    );

    expect(progress, isNotEmpty);
    expect(progress.first.etag, '"artifact-v1"');
    expect(progress.first.lastModified, isNull);
    expect(progress.first.resumable, isTrue);
  });
}
