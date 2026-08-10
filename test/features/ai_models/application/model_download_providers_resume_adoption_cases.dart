part of 'model_download_providers_test.dart';

void _registerModelDownloadResumeAdoptionCases() {
  test(
    'startDownload resumes a paused task from existing partial bytes for the same source',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final bridge = _RecordingEmbeddingRuntimeBridge();
      final downloadService = _FakeDownloadService(
        result: const ModelDownloadResult(
          localPath: '/models/embed-1.onnx',
          totalBytes: 4096,
          verifiedChecksum: 'sha256:verified-embed-1',
        ),
      );

      downloadRepository.tasksById['task-source-a'] = _buildTask(
        id: 'task-source-a',
        modelId: 'embed-1',
        sourceId: 'source-a',
        status: ModelDownloadStatus.paused,
        downloadedBytes: 1536,
      );
      downloadService.setTarget(
        modelId: 'embed-1',
        sourceUrl: 'https://example.com/embed-1.onnx',
        existingBytes: 1536,
        localPath: '/partials/embed-1-source-a.partial',
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
                  url: 'https://example.com/embed-1.onnx',
                  checksum: 'sha256:verified-embed-1',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-a',
              label: '主镜像',
              url: 'https://example.com/embed-1.onnx',
              checksum: 'sha256:verified-embed-1',
            ),
          );

      expect(
        downloadService.inspectedKeys,
        contains('embed-1|https://example.com/embed-1.onnx'),
      );
      expect(downloadService.lastResumeFromBytes, 1536);
      expect(
        downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status,
        ModelDownloadStatus.completed,
      );
    },
  );

  test(
    'modelRegistryEntriesProvider keeps legacy multimodal cleanup entries but skips catalog adoption',
    () async {
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      const registryMultimodalPath = '/models/legacy-multimodal.gguf';
      const catalogMultimodalPath = '/models/catalog-multimodal.gguf';
      const catalogMultimodalUrl =
          'https://example.com/catalog-multimodal.gguf';
      const embeddingPath = '/models/embed-1.onnx';

      registryRepository.entries['legacy-multimodal'] =
          const ModelRegistryEntry(
            id: 'legacy-multimodal',
            type: 'multimodal_llm',
            provider: 'legacy',
            name: 'Legacy Multimodal',
            version: '1.0.0',
            sizeBytes: 8192,
            quantization: 'Q4',
            minRamMb: 4096,
            recommendedTier: 'local_multimodal',
            localPath: registryMultimodalPath,
            checksum: 'sha256:legacy-multimodal',
            enabled: true,
            installedAt: null,
            filePresent: true,
          );
      registryRepository.entries['embed-1'] = const ModelRegistryEntry(
        id: 'embed-1',
        type: 'embedding',
        provider: 'builtin_catalog',
        name: 'MiniLM Embedding',
        version: '1.0.0',
        sizeBytes: 4096,
        quantization: 'Q8',
        minRamMb: 512,
        recommendedTier: 'mvp',
        localPath: embeddingPath,
        checksum: _embeddingChecksum,
        enabled: true,
        installedAt: null,
        filePresent: true,
      );
      downloadService.existingPaths.addAll(<String>[
        registryMultimodalPath,
        embeddingPath,
      ]);
      downloadService.setTarget(
        modelId: 'catalog-multimodal',
        sourceUrl: catalogMultimodalUrl,
        existingBytes: 8192,
        localPath: catalogMultimodalPath,
      );
      downloadService.checksumProbeFailurePaths.addAll(<String>{
        registryMultimodalPath,
        catalogMultimodalPath,
      });

      final container = _modelProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          modelCatalogRepositoryProvider.overrideWithValue(
            _MemoryCatalogRepository(const <ModelCatalogEntry>[
              ModelCatalogEntry(
                id: 'catalog-multimodal',
                type: 'multimodal_llm',
                tier: 'local_multimodal',
                displayName: 'Catalog Multimodal',
                description: 'Legacy catalog entry.',
                sizeBytes: 8192,
                minRamMb: 4096,
                recommendedTier: 'local_multimodal',
                sources: <ModelSourceEntry>[
                  ModelSourceEntry(
                    id: 'catalog-multimodal-source',
                    label: 'Catalog source',
                    url: catalogMultimodalUrl,
                    checksum: 'sha256:catalog-multimodal',
                  ),
                ],
              ),
            ]),
          ),
        ],
      );

      addTearDown(container.dispose);

      final entries = await container.read(modelRegistryEntriesProvider.future);

      expect(
        <String, bool>{
          'returned multimodal': entries.any(
            (entry) => entry.id == 'legacy-multimodal',
          ),
          'called fileExists': downloadService.fileExistsPaths.contains(
            registryMultimodalPath,
          ),
          'called registry checksum': downloadService.verifiedPaths.contains(
            registryMultimodalPath,
          ),
          'inspected catalog': downloadService.inspectedKeys.contains(
            'catalog-multimodal|$catalogMultimodalUrl',
          ),
          'called catalog checksum': downloadService.verifiedPaths.contains(
            catalogMultimodalPath,
          ),
        },
        <String, bool>{
          'returned multimodal': true,
          'called fileExists': false,
          'called registry checksum': false,
          'inspected catalog': false,
          'called catalog checksum': false,
        },
      );
      final legacy = entries.singleWhere(
        (entry) => entry.id == 'legacy-multimodal',
      );
      expect(legacy.enabled, isTrue);
      expect(legacy.integrityStatus, ModelIntegrityStatus.unknown);
      expect(entries.map((entry) => entry.id), contains('embed-1'));
      expect(downloadService.fileExistsPaths, contains(embeddingPath));
      expect(downloadService.verifiedPaths, contains(embeddingPath));
    },
  );

  test(
    'modelRegistryEntriesProvider adopts a complete local llm file from catalog when registry entry is missing',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final catalogRepository = _MemoryCatalogRepository(
        const <ModelCatalogEntry>[
          ModelCatalogEntry(
            id: 'qwen-local',
            type: 'llm',
            tier: 'local',
            displayName: 'Qwen Local',
            description: '用于本地问答。',
            sizeBytes: 8192,
            minRamMb: 2048,
            recommendedTier: 'local',
            sources: <ModelSourceEntry>[
              ModelSourceEntry(
                id: 'source-1',
                label: '镜像源',
                url: 'https://example.com/qwen.gguf',
                checksum: _qwenChecksum,
              ),
            ],
          ),
        ],
      );

      downloadService.existingPaths.add('/models/qwen-local.gguf');
      downloadService.setTarget(
        modelId: 'qwen-local',
        sourceUrl: 'https://example.com/qwen.gguf',
        existingBytes: 8192,
        localPath: '/models/qwen-local.gguf',
      );

      final container = _modelProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
        ],
      );

      addTearDown(container.dispose);

      final entries = await container.read(modelRegistryEntriesProvider.future);
      final adopted = entries.singleWhere((entry) => entry.id == 'qwen-local');

      expect(adopted.localPath, '/models/qwen-local.gguf');
      expect(adopted.checksum, _qwenChecksum);
      expect(adopted.sizeBytes, 8192);
      expect(adopted.filePresent, isTrue);
      expect(adopted.integrityStatus, ModelIntegrityStatus.valid);
      expect(adopted.enabled, isTrue);
      expect(
        registryRepository.entries['qwen-local']?.localPath,
        '/models/qwen-local.gguf',
      );
      final adoptedTask = downloadRepository.tasksByModelAndSource(
        'qwen-local',
        'source-1',
      );
      expect(adoptedTask?.id, 'adopted:qwen-local:source-1');
      expect(adoptedTask?.status, ModelDownloadStatus.completed);

      container.invalidate(modelRegistryEntriesProvider);
      await container.read(modelRegistryEntriesProvider.future);
      expect(downloadRepository.tasksById, hasLength(1));
    },
  );

  test(
    'modelRegistryEntriesProvider adopts a checksum-valid local llm file even when catalog size is stale',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final catalogRepository = _MemoryCatalogRepository(
        const <ModelCatalogEntry>[
          ModelCatalogEntry(
            id: 'qwen-local',
            type: 'llm',
            tier: 'local',
            displayName: 'Qwen Local',
            description: '用于本地问答。',
            sizeBytes: 16384,
            minRamMb: 2048,
            recommendedTier: 'local',
            sources: <ModelSourceEntry>[
              ModelSourceEntry(
                id: 'source-1',
                label: '镜像源',
                url: 'https://example.com/qwen.gguf',
                checksum: _qwenChecksum,
              ),
            ],
          ),
        ],
      );

      downloadService.existingPaths.add('/models/qwen-local.gguf');
      downloadService.setTarget(
        modelId: 'qwen-local',
        sourceUrl: 'https://example.com/qwen.gguf',
        existingBytes: 8192,
        localPath: '/models/qwen-local.gguf',
      );

      final container = _modelProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
        ],
      );

      addTearDown(container.dispose);

      final entries = await container.read(modelRegistryEntriesProvider.future);
      final adopted = entries.singleWhere((entry) => entry.id == 'qwen-local');

      expect(adopted.localPath, '/models/qwen-local.gguf');
      expect(adopted.checksum, _qwenChecksum);
      expect(adopted.sizeBytes, 8192);
      expect(adopted.filePresent, isTrue);
      expect(adopted.integrityStatus, ModelIntegrityStatus.valid);
      expect(adopted.enabled, isTrue);
      expect(
        downloadRepository
            .tasksByModelAndSource('qwen-local', 'source-1')
            ?.status,
        ModelDownloadStatus.completed,
      );
    },
  );

  test(
    'startDownload adopts pre-existing complete local GGUF file matching size and checksum without re-downloading',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final llmBridge = _RecordingLlmRuntimeBridge();
      final downloadService = _FakeDownloadService();

      // Pre-existing complete GGUF file at target path
      // File size matches catalog entry sizeBytes
      // Checksum will pass verification
      downloadService.existingPaths.add('/models/qwen.gguf');
      downloadService.setTarget(
        modelId: 'qwen-local',
        sourceUrl: 'https://example.com/qwen.gguf',
        existingBytes: 8192,
        localPath: '/models/qwen.gguf',
      );

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .startDownload(
            entry: const ModelCatalogEntry(
              id: 'qwen-local',
              type: 'llm',
              tier: 'local',
              displayName: 'Qwen Local',
              description: '用于本地问答。',
              sizeBytes: 8192,
              minRamMb: 2048,
              recommendedTier: 'local',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-1',
                  label: '镜像源',
                  url: 'https://example.com/qwen.gguf',
                  checksum: _qwenChecksum,
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-1',
              label: '镜像源',
              url: 'https://example.com/qwen.gguf',
              checksum: _qwenChecksum,
            ),
          );

      // No download should have been triggered
      expect(downloadService.invocations, isEmpty);
      // Registry should be written with the local path and valid checksum
      expect(registryRepository.entries['qwen-local'], isNotNull);
      expect(
        registryRepository.entries['qwen-local']?.localPath,
        '/models/qwen.gguf',
      );
      expect(registryRepository.entries['qwen-local']?.checksum, _qwenChecksum);
      expect(registryRepository.entries['qwen-local']?.sizeBytes, 8192);
      expect(
        registryRepository.entries['qwen-local']?.integrityStatus,
        ModelIntegrityStatus.valid,
      );
      expect(registryRepository.entries['qwen-local']?.enabled, isTrue);
      // Task should be marked completed
      expect(
        downloadRepository
            .tasksByModelAndSource('qwen-local', 'source-1')
            ?.status,
        ModelDownloadStatus.completed,
      );
      // LLM runtime ensureModelReady should have been called for llm entry
      expect(llmBridge.ensureCalls, 1);
      expect(llmBridge.lastModelId, 'qwen-local');
      expect(llmBridge.lastModelPath, '/models/qwen.gguf');
    },
  );
}
