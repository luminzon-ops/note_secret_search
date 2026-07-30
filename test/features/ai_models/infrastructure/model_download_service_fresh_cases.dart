part of 'model_download_service_test.dart';

void _registerModelDownloadServiceFreshCases() {
  test(
    'inspectDownloadTarget preserves final path and exposes staging target',
    () async {
      final tempDir = await _createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final service = _serviceFor(tempDir);

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
      final tempDir = await _createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final service = _serviceFor(tempDir);

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
      final tempDir = await _createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final service = _serviceFor(tempDir);
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
      final tempDir = await _createTempDir();
      addTearDown(() => tempDir.delete(recursive: true));
      final service = _serviceFor(tempDir);

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
      final tempDir = await _createTempDir();
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
      final service = _serviceFor(tempDir);
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
        expectedChecksum: _checksumFor(bytes),
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
          expectedChecksum: _checksumFor(bytes),
          expectedSizeBytes: bytes.length + 1,
          onProgress: (_) {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(await File(target.stagingPath).exists(), isFalse);
      expect(await File(target.metadataPath).exists(), isFalse);
    },
  );
}
