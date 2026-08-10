part of 'model_download_service_test.dart';

void _registerModelDownloadServiceResumeValidatorCases() {
  test(
    'stageArtifact resumes only the matching operation artifact and source',
    () async {
      final tempDir = await _createTempDir();
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
      final service = _serviceFor(tempDir);
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
        expectedChecksum: _checksumFor(bytes),
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
        expectedChecksum: _checksumFor(bytes),
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
      final tempDir = await _createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final bytes = <int>[2, 4, 6, 8];
      final fixture = await ModelDownloadHttpFixture.start(
        <ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(statusCode: HttpStatus.ok, body: bytes),
        ],
      );
      addTearDown(fixture.close);
      final service = _serviceFor(tempDir);
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
        expectedChecksum: _checksumFor(bytes),
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
        expectedChecksum: _checksumFor(bytes),
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
      final tempDir = await _createTempDir();
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
      final service = _serviceFor(tempDir);
      final sourceUrl = fixture.uri().toString();
      final target = await service.resolveStagingTarget(
        modelId: 'embed-1',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 4),
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
        totalBytes: finalBytes.length,
        etag: '"v1"',
      );

      final result = await service.download(
        taskId: 'task-etag-resume',
        modelId: 'embed-1',
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
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
    final tempDir = await _createTempDir();
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
    final service = _serviceFor(tempDir);
    final sourceUrl = fixture.uri().toString();
    final target = await service.resolveStagingTarget(
      modelId: 'embed-2',
      sourceUrl: sourceUrl,
    );
    await seedModelDownloadPartial(
      target: target,
      bytes: finalBytes.sublist(0, 3),
      sourceUrl: sourceUrl,
      expectedChecksum: _checksumFor(finalBytes),
      totalBytes: finalBytes.length,
      lastModified: lastModified,
    );

    final result = await service.download(
      taskId: 'task-date-resume',
      modelId: 'embed-2',
      sourceUrl: sourceUrl,
      expectedChecksum: _checksumFor(finalBytes),
      resumeFromBytes: 3,
      onProgress: (_) {},
    );

    expect(fixture.requests.single.range, 'bytes=3-');
    expect(fixture.requests.single.ifRange, lastModified);
    expect(result.resumed, isTrue);
    expect(await File(target.localPath).readAsBytes(), finalBytes);
  });

  test('malformed Last-Modified does not make a download resumable', () async {
    final tempDir = await _createTempDir();
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
    final service = _serviceFor(tempDir);

    final result = await service.stageArtifact(
      taskId: 'task-invalid-date',
      modelId: 'model-1',
      operationId: 'operation-invalid-date',
      artifactId: 'model',
      sourceUrl: fixture.uri('/model.bin').toString(),
      expectedChecksum: _checksumFor(bytes),
      expectedSizeBytes: bytes.length,
      onProgress: (_) {},
    );

    expect(result.resumable, isFalse);
  });

  test(
    'partial without a validator is not resumable and restarts from zero',
    () async {
      final tempDir = await _createTempDir();
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
      final service = _serviceFor(tempDir);
      final sourceUrl = fixture.uri().toString();
      final target = await service.resolveStagingTarget(
        modelId: 'missing-validator',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
        totalBytes: finalBytes.length,
      );

      final result = await service.download(
        taskId: 'task-no-validator',
        modelId: 'missing-validator',
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
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
}
