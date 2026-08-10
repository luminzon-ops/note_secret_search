part of 'model_download_providers_test.dart';

void _registerModelDownloadFailoverCases() {
  test(
    'startDownload keeps source-specific tasks separate for the same model',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final bridge = _RecordingEmbeddingRuntimeBridge();
      final downloadService = _FakeDownloadService(
        result: const ModelDownloadResult(
          localPath: '/models/embed-1.onnx',
          totalBytes: 4096,
          verifiedChecksum: 'sha256:verified-source-b',
        ),
      );

      downloadRepository.tasksById['task-source-a'] = _buildTask(
        id: 'task-source-a',
        modelId: 'embed-1',
        sourceId: 'source-a',
        status: ModelDownloadStatus.paused,
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'embed-1',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'MiniLM Embedding',
              description: '用于本地语义检索。',
              sizeBytes: 4096,
              minRamMb: 512,
              recommendedTier: 'mvp',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-b',
                  label: '备选镜像',
                  url: 'https://example.com/embed-1-b.onnx',
                  checksum: 'sha256:verified-source-b',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-b',
              label: '备选镜像',
              url: 'https://example.com/embed-1-b.onnx',
              checksum: 'sha256:verified-source-b',
            ),
          );

      expect(
        downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status,
        ModelDownloadStatus.paused,
      );
      expect(
        downloadRepository.tasksByModelAndSource('embed-1', 'source-b')?.status,
        ModelDownloadStatus.completed,
      );
    },
  );

  test('pause only affects the latest task for the selected source', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final downloadService = _FakeDownloadService(
      result: const ModelDownloadResult(
        localPath: '/models/embed-1.onnx',
        totalBytes: 4096,
        verifiedChecksum: 'sha256:verified-source-a',
      ),
    );

    downloadRepository.tasksById['task-source-a'] = _buildTask(
      id: 'task-source-a',
      modelId: 'embed-1',
      sourceId: 'source-a',
      status: ModelDownloadStatus.downloading,
    );
    downloadRepository.tasksById['task-source-b'] = _buildTask(
      id: 'task-source-b',
      modelId: 'embed-1',
      sourceId: 'source-b',
      status: ModelDownloadStatus.downloading,
    );

    final container = _modelProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
      ],
    );

    addTearDown(container.dispose);

    await container
        .read(modelDownloadControllerProvider)
        .pause('embed-1', sourceId: 'source-b');

    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status,
      ModelDownloadStatus.downloading,
    );
    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-b')?.status,
      ModelDownloadStatus.paused,
    );
  });

  test(
    'startDownload retries fallback source when selected source fails with checksum mismatch',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final bridge = _RecordingEmbeddingRuntimeBridge();
      final downloadService = _FakeDownloadService();

      downloadService.setErrorForSource(
        sourceUrl: 'https://example.com/embed-1-a.onnx',
        error: StateError('Checksum mismatch for source-a'),
      );
      downloadService.setResultForSource(
        sourceUrl: 'https://example.com/embed-1-b.onnx',
        result: const ModelDownloadResult(
          localPath: '/models/embed-1.onnx',
          totalBytes: 4096,
          verifiedChecksum: 'sha256:verified-source-b',
        ),
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'embed-1',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'MiniLM Embedding',
              description: '用于本地语义检索。',
              sizeBytes: 4096,
              minRamMb: 512,
              recommendedTier: 'mvp',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-a',
                  label: '主镜像',
                  url: 'https://example.com/embed-1-a.onnx',
                  checksum: 'sha256:verified-source-a',
                ),
                ModelSourceEntry(
                  id: 'source-b',
                  label: '备用镜像',
                  url: 'https://example.com/embed-1-b.onnx',
                  checksum: 'sha256:verified-source-b',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-a',
              label: '主镜像',
              url: 'https://example.com/embed-1-a.onnx',
              checksum: 'sha256:verified-source-a',
            ),
          );

      expect(downloadService.invocations.length, 2);
      expect(
        downloadService.invocations[0].sourceUrl,
        'https://example.com/embed-1-a.onnx',
      );
      expect(
        downloadService.invocations[1].sourceUrl,
        'https://example.com/embed-1-b.onnx',
      );
      expect(
        downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status,
        ModelDownloadStatus.failed,
      );
      expect(
        downloadRepository.tasksByModelAndSource('embed-1', 'source-b')?.status,
        ModelDownloadStatus.completed,
      );
      expect(
        registryRepository.entries['embed-1']?.checksum,
        'sha256:verified-source-b',
      );
    },
  );

  test(
    'startDownload resets resumeFromBytes to zero when switching to a different source',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final bridge = _RecordingEmbeddingRuntimeBridge();
      final downloadService = _FakeDownloadService();

      downloadService.setErrorForSource(
        sourceUrl: 'https://example.com/embed-1-a.onnx',
        error: StateError('Checksum mismatch for source-a'),
      );
      downloadService.setResultForSource(
        sourceUrl: 'https://example.com/embed-1-b.onnx',
        result: const ModelDownloadResult(
          localPath: '/models/embed-1.onnx',
          totalBytes: 4096,
          verifiedChecksum: 'sha256:verified-source-b',
        ),
      );
      downloadService.setTarget(
        modelId: 'embed-1',
        sourceUrl: 'https://example.com/embed-1-a.onnx',
        existingBytes: 1024,
        localPath: '/partials/embed-1.partial',
      );
      downloadService.setTarget(
        modelId: 'embed-1',
        sourceUrl: 'https://example.com/embed-1-b.onnx',
        existingBytes: 2048,
        localPath: '/partials/embed-1.partial',
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'embed-1',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'MiniLM Embedding',
              description: '用于本地语义检索。',
              sizeBytes: 4096,
              minRamMb: 512,
              recommendedTier: 'mvp',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-a',
                  label: '主镜像',
                  url: 'https://example.com/embed-1-a.onnx',
                  checksum: 'sha256:verified-source-a',
                ),
                ModelSourceEntry(
                  id: 'source-b',
                  label: '备用镜像',
                  url: 'https://example.com/embed-1-b.onnx',
                  checksum: 'sha256:verified-source-b',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-a',
              label: '主镜像',
              url: 'https://example.com/embed-1-a.onnx',
              checksum: 'sha256:verified-source-a',
            ),
          );

      expect(downloadService.invocations.length, 2);
      expect(downloadService.invocations[0].resumeFromBytes, 1024);
      expect(downloadService.invocations[1].resumeFromBytes, 0);
    },
  );

  test(
    'startDownload probes fallback sources and prefers healthier fallback ordering after selected source fails',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final bridge = _RecordingEmbeddingRuntimeBridge();
      final downloadService = _FakeDownloadService();
      final probeService = _FakeModelSourceProbeService();

      downloadService.setErrorForSource(
        sourceUrl: 'https://example.com/embed-1-a.onnx',
        error: StateError('Checksum mismatch for source-a'),
      );
      downloadService.setResultForSource(
        sourceUrl: 'https://example.com/embed-1-c.onnx',
        result: const ModelDownloadResult(
          localPath: '/models/embed-1.onnx',
          totalBytes: 4096,
          verifiedChecksum: 'sha256:verified-source-c',
        ),
      );

      probeService.setResult(
        const ModelSourceProbeResult(
          sourceId: 'source-b',
          reachable: true,
          statusCode: 200,
          contentLength: 4096,
          rangeSupported: false,
          latencyMs: 180,
          usedFallbackRangeProbe: false,
        ),
      );
      probeService.setResult(
        const ModelSourceProbeResult(
          sourceId: 'source-c',
          reachable: true,
          statusCode: 200,
          contentLength: 4096,
          rangeSupported: true,
          latencyMs: 40,
          usedFallbackRangeProbe: false,
        ),
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          modelSourceProbeServiceProvider.overrideWithValue(probeService),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'embed-1',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'MiniLM Embedding',
              description: '用于本地语义检索。',
              sizeBytes: 4096,
              minRamMb: 512,
              recommendedTier: 'mvp',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-a',
                  label: '主镜像',
                  url: 'https://example.com/embed-1-a.onnx',
                  checksum: 'sha256:verified-source-a',
                ),
                ModelSourceEntry(
                  id: 'source-b',
                  label: '次优镜像',
                  url: 'https://example.com/embed-1-b.onnx',
                  checksum: 'sha256:verified-source-b',
                ),
                ModelSourceEntry(
                  id: 'source-c',
                  label: '健康镜像',
                  url: 'https://example.com/embed-1-c.onnx',
                  checksum: 'sha256:verified-source-c',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-a',
              label: '主镜像',
              url: 'https://example.com/embed-1-a.onnx',
              checksum: 'sha256:verified-source-a',
            ),
          );

      expect(downloadService.invocations.length, 2);
      expect(
        downloadService.invocations[0].sourceUrl,
        'https://example.com/embed-1-a.onnx',
      );
      expect(
        downloadService.invocations[1].sourceUrl,
        'https://example.com/embed-1-c.onnx',
      );
      expect(
        downloadRepository.tasksByModelAndSource('embed-1', 'source-b'),
        isNull,
      );
      expect(
        downloadRepository.tasksByModelAndSource('embed-1', 'source-c')?.status,
        ModelDownloadStatus.completed,
      );
    },
  );
}
