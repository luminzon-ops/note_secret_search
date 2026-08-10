part of 'model_download_service_test.dart';

void _registerModelDownloadServiceRestartErrorCases() {
  test('200, 412, and 416 after Range restart from zero', () async {
    final cases = <int>[
      HttpStatus.ok,
      HttpStatus.preconditionFailed,
      HttpStatus.requestedRangeNotSatisfiable,
    ];
    final finalBytes = <int>[2, 4, 6, 8, 10, 12];

    for (final firstStatus in cases) {
      final tempDir = await _createTempDir();
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
      final service = _serviceFor(tempDir);
      final target = await service.resolveStagingTarget(
        modelId: 'restart-$firstStatus',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
        totalBytes: finalBytes.length,
        etag: '"v1"',
      );

      final result = await service.download(
        taskId: 'task-restart-$firstStatus',
        modelId: 'restart-$firstStatus',
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
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
      final tempDir = await _createTempDir();
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
      final service = _serviceFor(tempDir);
      final target = await service.resolveStagingTarget(
        modelId: 'invalid-range',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
        totalBytes: finalBytes.length,
        etag: '"v1"',
      );

      final result = await service.download(
        taskId: 'task-invalid-range',
        modelId: 'invalid-range',
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
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
      final tempDir = await _createTempDir();
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
      final service = _serviceFor(tempDir);
      final target = await service.resolveStagingTarget(
        modelId: 'validator-change',
        sourceUrl: sourceUrl,
      );
      await seedModelDownloadPartial(
        target: target,
        bytes: finalBytes.sublist(0, 3),
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
        totalBytes: finalBytes.length,
        etag: '"v1"',
      );

      final result = await service.download(
        taskId: 'task-validator-change',
        modelId: 'validator-change',
        sourceUrl: sourceUrl,
        expectedChecksum: _checksumFor(finalBytes),
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
    final tempDir = await _createTempDir();
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
    final service = _serviceFor(tempDir);
    final sourceUrl = fixture.uri().toString();
    final target = await service.resolveStagingTarget(
      modelId: 'short-206',
      sourceUrl: sourceUrl,
    );
    await seedModelDownloadPartial(
      target: target,
      bytes: finalBytes.sublist(0, 3),
      sourceUrl: sourceUrl,
      expectedChecksum: _checksumFor(finalBytes),
      totalBytes: finalBytes.length,
      etag: '"v1"',
    );

    final result = await service.download(
      taskId: 'task-short-206',
      modelId: 'short-206',
      sourceUrl: sourceUrl,
      expectedChecksum: _checksumFor(finalBytes),
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
      final tempDir = await _createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      const oldBytes = <int>[9, 9, 9];
      final newBytes = <int>[1, 2, 3, 4];
      final fixture = await ModelDownloadHttpFixture.start(
        <ModelDownloadHttpResponse>[
          ModelDownloadHttpResponse(statusCode: HttpStatus.ok, body: newBytes),
        ],
      );
      addTearDown(fixture.close);
      final service = _serviceFor(tempDir);
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
          expectedChecksum: _checksumFor(oldBytes),
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
    final tempDir = await _createTempDir();
    addTearDown(() => tempDir.delete(recursive: true));
    final bytes = <int>[1, 2, 3, 4];
    final fixture = await ModelDownloadHttpFixture.start(
      <ModelDownloadHttpResponse>[
        ModelDownloadHttpResponse(statusCode: HttpStatus.ok, body: bytes),
      ],
    );
    addTearDown(fixture.close);
    final service = _serviceFor(tempDir);
    var progressCompleted = false;

    final result = await service.download(
      taskId: 'task-async-progress',
      modelId: 'embed-1',
      sourceUrl: fixture.uri().toString(),
      expectedChecksum: _checksumFor(bytes),
      onProgress: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        progressCompleted = true;
      },
    );

    expect(progressCompleted, isTrue);
    expect(result.totalBytes, bytes.length);
  });

  test('server errors are not converted into a restart', () async {
    final tempDir = await _createTempDir();
    addTearDown(() => tempDir.delete(recursive: true));
    final fixture =
        await ModelDownloadHttpFixture.start(<ModelDownloadHttpResponse>[
          const ModelDownloadHttpResponse(
            statusCode: HttpStatus.internalServerError,
          ),
        ]);
    addTearDown(fixture.close);
    final service = _serviceFor(tempDir);

    await expectLater(
      service.download(
        taskId: 'task-server-error',
        modelId: 'server-error',
        sourceUrl: fixture.uri().toString(),
        expectedChecksum: _checksumFor(<int>[1]),
        onProgress: (_) {},
      ),
      throwsA(isA<DioException>()),
    );
    expect(fixture.requests, hasLength(1));
  });
}
