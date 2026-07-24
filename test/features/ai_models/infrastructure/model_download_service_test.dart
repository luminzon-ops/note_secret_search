import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';

import 'model_download_http_fixture.dart';

void main() {
  String checksumFor(List<int> bytes) {
    return 'sha256:${sha256.convert(bytes).toString()}';
  }

  ModelDownloadService serviceFor(Directory tempDir) {
    return ModelDownloadService(
      dio: Dio(),
      logger: const AppLogger(),
      applicationSupportDirectoryProvider: () async => tempDir,
    );
  }

  Future<Directory> createTempDir() {
    return Directory.systemTemp.createTemp('model-download-service');
  }

  test(
    'inspectDownloadTarget preserves final path and exposes staging target',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final service = serviceFor(tempDir);

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
      final stagingTarget = await service.resolveStagingTarget(
        modelId: 'embed-1',
        sourceUrl: 'https://example.com/embed-1.onnx',
      );
      expect(
        stagingTarget.stagingPath.replaceAll('\\', '/'),
        contains('/models/embed-1/.staging/'),
      );
    },
  );

  test(
    'staging target uses source-specific filenames for multimodal artifacts',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final service = serviceFor(tempDir);

      final modelTarget = await service.resolveStagingTarget(
        modelId: 'minicpm_v_4_6_q4_k_m',
        sourceUrl:
            'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/MiniCPM-V-4_6-Q4_K_M.gguf',
      );
      final mmprojTarget = await service.resolveStagingTarget(
        modelId: 'minicpm_v_4_6_q4_k_m',
        sourceUrl:
            'https://hf-mirror.com/openbmb/MiniCPM-V-4.6-gguf/resolve/main/mmproj-model-f16.gguf',
      );

      expect(modelTarget.localPath, isNot(mmprojTarget.localPath));
      expect(
        modelTarget.localPath.replaceAll('\\', '/'),
        contains('MiniCPM-V-4_6-Q4_K_M.gguf'),
      );
      expect(
        mmprojTarget.localPath.replaceAll('\\', '/'),
        contains('mmproj-model-f16.gguf'),
      );
      expect(modelTarget.stagingPath, isNot(mmprojTarget.stagingPath));
      expect(await Directory('${tempDir.path}/models').exists(), isFalse);
    },
  );

  test(
    'inspectDownloadTarget does not create a missing model directory',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final service = serviceFor(tempDir);
      final modelDirectory = Directory('${tempDir.path}/models/missing-model');

      final target = await service.inspectDownloadTarget(
        modelId: 'missing-model',
        sourceUrl: 'https://example.com/model.gguf',
      );

      expect(target.exists, isFalse);
      expect(target.existingBytes, 0);
      expect(await modelDirectory.exists(), isFalse);
    },
  );

  test(
    'artifact staging target is bound to operation and artifact identity',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final service = serviceFor(tempDir);

      final model = await service.resolveArtifactStagingTarget(
        modelId: 'model-1',
        operationId: 'operation-1',
        artifactId: 'model',
      );
      final tokenizer = await service.resolveArtifactStagingTarget(
        modelId: 'model-1',
        operationId: 'operation-1',
        artifactId: 'tokenizer',
      );

      expect(
        model.stagingPath.replaceAll('\\', '/'),
        endsWith('/models/model-1/.staging/operation-1/model.part'),
      );
      expect(
        model.metadataPath.replaceAll('\\', '/'),
        endsWith('/models/model-1/.staging/operation-1/model.json'),
      );
      expect(tokenizer.stagingPath, isNot(model.stagingPath));
      expect(await Directory('${tempDir.path}/models').exists(), isFalse);
    },
  );

  test(
    'stageArtifact verifies signed size without publishing a final file',
    () async {
      final tempDir = await createTempDir();
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
      final service = serviceFor(tempDir);
      final target = await service.resolveArtifactStagingTarget(
        modelId: 'model-1',
        operationId: 'operation-1',
        artifactId: 'model',
      );

      final result = await service.stageArtifact(
        taskId: 'task-1',
        modelId: 'model-1',
        operationId: 'operation-1',
        artifactId: 'model',
        sourceUrl: fixture.uri('/model.bin').toString(),
        expectedChecksum: checksumFor(bytes),
        expectedSizeBytes: bytes.length,
        onProgress: (_) {},
      );

      expect(result.localPath, target.stagingPath);
      expect(await File(target.stagingPath).readAsBytes(), bytes);
      expect(await File(target.metadataPath).exists(), isTrue);
      expect(
        await File('${tempDir.path}/models/model-1/model.bin').exists(),
        isFalse,
      );
    },
  );

  test(
    'stageArtifact clears staging when signed size does not match',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final bytes = <int>[1, 2, 3, 4];
      final fixture = await ModelDownloadHttpFixture.start(
        <ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(statusCode: HttpStatus.ok, body: bytes),
        ],
      );
      addTearDown(fixture.close);
      final service = serviceFor(tempDir);
      final target = await service.resolveArtifactStagingTarget(
        modelId: 'model-1',
        operationId: 'operation-2',
        artifactId: 'model',
      );

      await expectLater(
        service.stageArtifact(
          taskId: 'task-size-mismatch',
          modelId: 'model-1',
          operationId: 'operation-2',
          artifactId: 'model',
          sourceUrl: fixture.uri('/model.bin').toString(),
          expectedChecksum: checksumFor(bytes),
          expectedSizeBytes: bytes.length + 1,
          onProgress: (_) {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(await File(target.stagingPath).exists(), isFalse);
      expect(await File(target.metadataPath).exists(), isFalse);
    },
  );

  test(
    'stageArtifact resumes only the matching operation artifact and source',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final bytes = <int>[1, 2, 3, 4, 5, 6];
      final fixture =
          await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
            ModelDownloadHttpResponse(
              statusCode: HttpStatus.partialContent,
              body: bytes.sublist(3),
              etag: '"artifact-v1"',
              contentRange: 'bytes 3-5/6',
            ),
          ]);
      addTearDown(fixture.close);
      final service = serviceFor(tempDir);
      final sourceUrl = fixture.uri('/model.bin').toString();
      final target = await service.resolveArtifactStagingTarget(
        modelId: 'model-1',
        operationId: 'operation-3',
        artifactId: 'model',
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: bytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(bytes),
        totalBytes: bytes.length,
        modelId: 'model-1',
        operationId: 'operation-3',
        artifactId: 'model',
        expectedSizeBytes: bytes.length,
        etag: '"artifact-v1"',
      );

      final result = await service.stageArtifact(
        taskId: 'task-resume',
        modelId: 'model-1',
        operationId: 'operation-3',
        artifactId: 'model',
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(bytes),
        expectedSizeBytes: bytes.length,
        resumeFromBytes: 3,
        onProgress: (_) {},
      );

      expect(fixture.requests.single.range, 'bytes=3-');
      expect(fixture.requests.single.ifRange, '"artifact-v1"');
      expect(result.resumed, isTrue);
      expect(await File(target.stagingPath).readAsBytes(), bytes);
    },
  );

  test(
    'stageArtifact clears a different source partial before failover',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final bytes = <int>[2, 4, 6, 8];
      final fixture = await ModelDownloadHttpFixture.start(
        <ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(statusCode: HttpStatus.ok, body: bytes),
        ],
      );
      addTearDown(fixture.close);
      final service = serviceFor(tempDir);
      final sourceUrl = fixture.uri('/mirror-b.bin').toString();
      final target = await service.resolveArtifactStagingTarget(
        modelId: 'model-1',
        operationId: 'operation-4',
        artifactId: 'model',
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: bytes.sublist(0, 2),
        sourceUrl: 'https://mirror-a.example/model.bin',
        expectedChecksum: checksumFor(bytes),
        totalBytes: bytes.length,
        modelId: 'model-1',
        operationId: 'operation-4',
        artifactId: 'model',
        expectedSizeBytes: bytes.length,
        etag: '"mirror-a"',
      );

      final result = await service.stageArtifact(
        taskId: 'task-failover',
        modelId: 'model-1',
        operationId: 'operation-4',
        artifactId: 'model',
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(bytes),
        expectedSizeBytes: bytes.length,
        resumeFromBytes: 2,
        onProgress: (_) {},
      );

      expect(fixture.requests.single.range, isNull);
      expect(result.resumed, isFalse);
      expect(result.fellBackToRestart, isTrue);
      expect(await File(target.stagingPath).readAsBytes(), bytes);
    },
  );

  test(
    'download resumes with Range, If-Range, ETag, and Content-Range',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final finalBytes = <int>[1, 2, 3, 4, 5, 6, 7, 8];
      final fixture =
          await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
            ModelDownloadHttpResponse(
              statusCode: HttpStatus.partialContent,
              body: finalBytes.sublist(4),
              etag: '"v1"',
              contentRange: 'bytes 4-7/8',
            ),
          ]);
      addTearDown(fixture.close);
      final service = serviceFor(tempDir);
      final sourceUrl = fixture.uri().toString();
      final target = await service.resolveStagingTarget(
        modelId: 'embed-1',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 4),
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        totalBytes: finalBytes.length,
        etag: '"v1"',
      );

      final result = await service.download(
        taskId: 'task-etag-resume',
        modelId: 'embed-1',
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        resumeFromBytes: 4,
        onProgress: (_) {},
      );

      expect(fixture.requests.single.range, 'bytes=4-');
      expect(fixture.requests.single.ifRange, '"v1"');
      expect(await File(target.localPath).readAsBytes(), finalBytes);
      expect(await File(target.stagingPath).exists(), isFalse);
      expect(await File(target.metadataPath).exists(), isFalse);
      expect(result.resumed, isTrue);
      expect(result.fellBackToRestart, isFalse);
      expect(result.resumable, isTrue);
    },
  );

  test('download resumes with Last-Modified when ETag is absent', () async {
    final tempDir = await createTempDir();
    addTearDown(() => tempDir.delete(recursive: true));
    final finalBytes = <int>[10, 11, 12, 13, 14, 15];
    const lastModified = 'Wed, 21 Oct 2015 07:28:00 GMT';
    final fixture =
        await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(
            statusCode: HttpStatus.partialContent,
            body: finalBytes.sublist(3),
            lastModified: lastModified,
            contentRange: 'bytes 3-5/6',
          ),
        ]);
    addTearDown(fixture.close);
    final service = serviceFor(tempDir);
    final sourceUrl = fixture.uri().toString();
    final target = await service.resolveStagingTarget(
      modelId: 'embed-2',
      sourceUrl: sourceUrl,
    );
    await seedModelDownloadPartial(
      target: target,
      bytes: finalBytes.sublist(0, 3),
      sourceUrl: sourceUrl,
      expectedChecksum: checksumFor(finalBytes),
      totalBytes: finalBytes.length,
      lastModified: lastModified,
    );

    final result = await service.download(
      taskId: 'task-date-resume',
      modelId: 'embed-2',
      sourceUrl: sourceUrl,
      expectedChecksum: checksumFor(finalBytes),
      resumeFromBytes: 3,
      onProgress: (_) {},
    );

    expect(fixture.requests.single.range, 'bytes=3-');
    expect(fixture.requests.single.ifRange, lastModified);
    expect(result.resumed, isTrue);
    expect(await File(target.localPath).readAsBytes(), finalBytes);
  });

  test('malformed Last-Modified does not make a download resumable', () async {
    final tempDir = await createTempDir();
    addTearDown(() => tempDir.delete(recursive: true));
    final bytes = <int>[1, 2, 3, 4];
    final fixture =
        await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(
            statusCode: HttpStatus.ok,
            body: bytes,
            lastModified: 'not-an-http-date',
          ),
        ]);
    addTearDown(fixture.close);
    final service = serviceFor(tempDir);

    final result = await service.stageArtifact(
      taskId: 'task-invalid-date',
      modelId: 'model-1',
      operationId: 'operation-invalid-date',
      artifactId: 'model',
      sourceUrl: fixture.uri('/model.bin').toString(),
      expectedChecksum: checksumFor(bytes),
      expectedSizeBytes: bytes.length,
      onProgress: (_) {},
    );

    expect(result.resumable, isFalse);
  });

  test(
    'partial without a validator is not resumable and restarts from zero',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final finalBytes = <int>[1, 3, 5, 7, 9, 11];
      final fixture = await ModelDownloadHttpFixture.start(
        <ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(
            statusCode: HttpStatus.ok,
            body: finalBytes,
          ),
        ],
      );
      addTearDown(fixture.close);
      final service = serviceFor(tempDir);
      final sourceUrl = fixture.uri().toString();
      final target = await service.resolveStagingTarget(
        modelId: 'missing-validator',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        totalBytes: finalBytes.length,
      );

      final result = await service.download(
        taskId: 'task-no-validator',
        modelId: 'missing-validator',
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        resumeFromBytes: 3,
        onProgress: (_) {},
      );

      expect(fixture.requests.single.range, isNull);
      expect(fixture.requests.single.ifRange, isNull);
      expect(result.resumed, isFalse);
      expect(result.fellBackToRestart, isTrue);
      expect(result.resumable, isFalse);
      expect(await File(target.localPath).readAsBytes(), finalBytes);
    },
  );

  test('200, 412, and 416 after Range restart from zero', () async {
    final cases = <int>[
      HttpStatus.ok,
      HttpStatus.preconditionFailed,
      HttpStatus.requestedRangeNotSatisfiable,
    ];
    final finalBytes = <int>[2, 4, 6, 8, 10, 12];

    for (final firstStatus in cases) {
      final tempDir = await createTempDir();
      final fixture =
          await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
            ModelDownloadHttpResponse(
              statusCode: firstStatus,
              body: firstStatus == HttpStatus.ok ? finalBytes : const <int>[],
              etag: firstStatus == HttpStatus.ok ? '"v2"' : null,
            ),
            ModelDownloadHttpResponse(
              statusCode: HttpStatus.ok,
              body: finalBytes,
            ),
          ]);
      final sourceUrl = fixture.uri().toString();
      addTearDown(() async {
        await fixture.close();
        await tempDir.delete(recursive: true);
      });
      final service = serviceFor(tempDir);
      final target = await service.resolveStagingTarget(
        modelId: 'restart-$firstStatus',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        totalBytes: finalBytes.length,
        etag: '"v1"',
      );

      final result = await service.download(
        taskId: 'task-restart-$firstStatus',
        modelId: 'restart-$firstStatus',
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        resumeFromBytes: 3,
        onProgress: (_) {},
      );

      expect(fixture.requests, hasLength(2));
      expect(fixture.requests.first.range, 'bytes=3-');
      expect(fixture.requests.first.ifRange, '"v1"');
      expect(fixture.requests.last.range, isNull);
      expect(result.fellBackToRestart, isTrue);
      expect(await File(target.localPath).readAsBytes(), finalBytes);
    }
  });

  test('invalid 206 Content-Range restarts from zero', () async {
    final cases = <String?>[
      'bytes 2-5/6',
      'bytes 3-5/7',
      'bytes 3-6/6',
      'bytes */6',
      null,
    ];
    final finalBytes = <int>[3, 6, 9, 12, 15, 18];

    for (final contentRange in cases) {
      final tempDir = await createTempDir();
      final fixture =
          await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
            ModelDownloadHttpResponse(
              statusCode: HttpStatus.partialContent,
              body: finalBytes.sublist(3),
              etag: '"v1"',
              contentRange: contentRange,
            ),
            ModelDownloadHttpResponse(
              statusCode: HttpStatus.ok,
              body: finalBytes,
            ),
          ]);
      final sourceUrl = fixture.uri().toString();
      addTearDown(() async {
        await fixture.close();
        await tempDir.delete(recursive: true);
      });
      final service = serviceFor(tempDir);
      final target = await service.resolveStagingTarget(
        modelId: 'invalid-range',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        totalBytes: finalBytes.length,
        etag: '"v1"',
      );

      final result = await service.download(
        taskId: 'task-invalid-range',
        modelId: 'invalid-range',
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        resumeFromBytes: 3,
        onProgress: (_) {},
      );

      expect(fixture.requests.last.range, isNull);
      expect(result.fellBackToRestart, isTrue);
      expect(await File(target.localPath).readAsBytes(), finalBytes);
    }
  });

  test('changed or missing validator in 206 restarts from zero', () async {
    final validatorHeaders = <Map<String, String>>[
      <String, String>{'etag': '"v2"'},
      <String, String>{},
    ];
    final finalBytes = <int>[4, 8, 12, 16, 20, 24];

    for (final headers in validatorHeaders) {
      final tempDir = await createTempDir();
      final first = ModelDownloadHttpResponse(
        statusCode: HttpStatus.partialContent,
        body: finalBytes.sublist(3),
        etag: headers['etag'],
        contentRange: 'bytes 3-5/6',
      );
      final fixture = await ModelDownloadHttpFixture.start(
        <ModelDownloadHttpResponse>[
          first,
          ModelDownloadHttpResponse(
            statusCode: HttpStatus.ok,
            body: finalBytes,
          ),
        ],
      );
      final sourceUrl = fixture.uri().toString();
      addTearDown(() async {
        await fixture.close();
        await tempDir.delete(recursive: true);
      });
      final service = serviceFor(tempDir);
      final target = await service.resolveStagingTarget(
        modelId: 'validator-change',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        totalBytes: finalBytes.length,
        etag: '"v1"',
      );

      final result = await service.download(
        taskId: 'task-validator-change',
        modelId: 'validator-change',
        sourceUrl: sourceUrl,
        expectedChecksum: checksumFor(finalBytes),
        resumeFromBytes: 3,
        onProgress: (_) {},
      );

      expect(result.resumed, isFalse);
      expect(result.fellBackToRestart, isTrue);
      expect(fixture.requests.last.range, isNull);
      expect(await File(target.localPath).readAsBytes(), finalBytes);
    }
  });

  test('short chunked 206 body restarts from zero', () async {
    final tempDir = await createTempDir();
    addTearDown(() => tempDir.delete(recursive: true));
    final finalBytes = <int>[1, 2, 3, 4, 5, 6];
    final fixture = await ModelDownloadHttpFixture.start(
      <ModelDownloadHttpResponse>[
        const ModelDownloadHttpResponse(
          statusCode: HttpStatus.partialContent,
          body: <int>[4, 5],
          etag: '"v1"',
          contentRange: 'bytes 3-5/6',
          includeContentLength: false,
        ),
        ModelDownloadHttpResponse(statusCode: HttpStatus.ok, body: finalBytes),
      ],
    );
    addTearDown(fixture.close);
    final service = serviceFor(tempDir);
    final sourceUrl = fixture.uri().toString();
    final target = await service.resolveStagingTarget(
      modelId: 'short-206',
      sourceUrl: sourceUrl,
    );
    await seedModelDownloadPartial(
      target: target,
      bytes: finalBytes.sublist(0, 3),
      sourceUrl: sourceUrl,
      expectedChecksum: checksumFor(finalBytes),
      totalBytes: finalBytes.length,
      etag: '"v1"',
    );

    final result = await service.download(
      taskId: 'task-short-206',
      modelId: 'short-206',
      sourceUrl: sourceUrl,
      expectedChecksum: checksumFor(finalBytes),
      resumeFromBytes: 3,
      onProgress: (_) {},
    );

    expect(fixture.requests, hasLength(2));
    expect(fixture.requests.first.range, 'bytes=3-');
    expect(fixture.requests.last.range, isNull);
    expect(result.resumed, isFalse);
    expect(result.fellBackToRestart, isTrue);
    expect(await File(target.localPath).readAsBytes(), finalBytes);
    expect(await File(target.stagingPath).exists(), isFalse);
    expect(await File(target.metadataPath).exists(), isFalse);
  });

  test(
    'checksum mismatch clears staging and preserves an existing final file',
    () async {
      final tempDir = await createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      const oldBytes = <int>[9, 9, 9];
      final newBytes = <int>[1, 2, 3, 4];
      final fixture = await ModelDownloadHttpFixture.start(
        <ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(statusCode: HttpStatus.ok, body: newBytes),
        ],
      );
      addTearDown(fixture.close);
      final service = serviceFor(tempDir);
      final sourceUrl = fixture.uri().toString();
      final target = await service.resolveStagingTarget(
        modelId: 'checksum-mismatch',
        sourceUrl: sourceUrl,
      );
      final oldFile = File(target.localPath);
      await oldFile.parent.create(recursive: true);
      await oldFile.writeAsBytes(oldBytes);

      await expectLater(
        service.download(
          taskId: 'task-checksum-mismatch',
          modelId: 'checksum-mismatch',
          sourceUrl: sourceUrl,
          expectedChecksum: checksumFor(oldBytes),
          onProgress: (_) {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(await File(target.localPath).readAsBytes(), oldBytes);
      expect(await File(target.stagingPath).exists(), isFalse);
      expect(await File(target.metadataPath).exists(), isFalse);
    },
  );

  test('download awaits async progress callbacks before completing', () async {
    final tempDir = await createTempDir();
    addTearDown(() => tempDir.delete(recursive: true));
    final bytes = <int>[1, 2, 3, 4];
    final fixture = await ModelDownloadHttpFixture.start(
      <ModelDownloadHttpResponse>[
        ModelDownloadHttpResponse(statusCode: HttpStatus.ok, body: bytes),
      ],
    );
    addTearDown(fixture.close);
    final service = serviceFor(tempDir);
    var progressCompleted = false;

    final result = await service.download(
      taskId: 'task-async-progress',
      modelId: 'embed-1',
      sourceUrl: fixture.uri().toString(),
      expectedChecksum: checksumFor(bytes),
      onProgress: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        progressCompleted = true;
      },
    );

    expect(progressCompleted, isTrue);
    expect(result.totalBytes, bytes.length);
  });

  test('server errors are not converted into a restart', () async {
    final tempDir = await createTempDir();
    addTearDown(() => tempDir.delete(recursive: true));
    final fixture =
        await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
          const ModelDownloadHttpResponse(
            statusCode: HttpStatus.internalServerError,
          ),
        ]);
    addTearDown(fixture.close);
    final service = serviceFor(tempDir);

    await expectLater(
      service.download(
        taskId: 'task-server-error',
        modelId: 'server-error',
        sourceUrl: fixture.uri().toString(),
        expectedChecksum: checksumFor(<int>[1]),
        onProgress: (_) {},
      ),
      throwsA(isA<DioException>()),
    );
    expect(fixture.requests, hasLength(1));
  });
}
