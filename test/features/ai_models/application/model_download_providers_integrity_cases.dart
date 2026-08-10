part of 'model_download_providers_test.dart';

void _registerModelDownloadIntegrityCases() {
  test(
    'modelRegistryEntriesProvider marks checksum-mismatched installed file as corrupted',
    () async {
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();

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
        localPath: '/models/embed-1.onnx',
        checksum: _embeddingChecksum,
        enabled: true,
        installedAt: null,
        filePresent: true,
      );
      downloadService.existingPaths.add('/models/embed-1.onnx');
      downloadService.checksumMismatchPaths.add('/models/embed-1.onnx');

      final container = _modelProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
        ],
      );

      addTearDown(container.dispose);

      final entries = await container.read(modelRegistryEntriesProvider.future);

      expect(entries.single.filePresent, isTrue);
      expect(entries.single.enabled, isFalse);
      expect(entries.single.integrityStatus, ModelIntegrityStatus.corrupted);
    },
  );

  test(
    'startDownload re-downloads a disabled installed model instead of short-circuiting on file presence',
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
        localPath: '/models/embed-1.onnx',
        checksum: _embeddingChecksum,
        enabled: false,
        installedAt: null,
        filePresent: true,
        integrityStatus: ModelIntegrityStatus.corrupted,
      );
      downloadService.existingPaths.add('/models/embed-1.onnx');

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

      expect(downloadService.deletedPaths, contains('/models/embed-1.onnx'));
      expect(downloadService.invocations, hasLength(1));
      expect(bridge.releasedModelIds, <String>['embed-1']);
    },
  );

  test(
    'embeddingRuntimeStatesProvider reports corrupted when installed embedding file fails checksum revalidation',
    () async {
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final bridge = _RecordingEmbeddingRuntimeBridge();

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
        localPath: '/models/embed-1.onnx',
        checksum: _embeddingChecksum,
        enabled: true,
        installedAt: null,
        filePresent: true,
      );
      downloadService.existingPaths.add('/models/embed-1.onnx');
      downloadService.checksumMismatchPaths.add('/models/embed-1.onnx');

      final container = _modelProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      final states = await container.read(
        embeddingRuntimeStatesProvider.future,
      );

      expect(states['embed-1']?.ready, isFalse);
      expect(states['embed-1']?.status, EmbeddingRuntimeStatus.corrupted);
      expect(states['embed-1']?.reason, contains('校验失败'));
      expect(bridge.inspectCalls, 0);
    },
  );

  test(
    'llmRuntimeStatesProvider reports corrupted when installed llm file fails checksum revalidation',
    () async {
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final bridge = _RecordingLlmRuntimeBridge();

      registryRepository.entries['llm-1'] = const ModelRegistryEntry(
        id: 'llm-1',
        type: 'llm',
        provider: 'builtin_catalog',
        name: 'Phi Local',
        version: '1.0.0',
        sizeBytes: 8192,
        quantization: 'Q4_K_M',
        minRamMb: 2048,
        recommendedTier: 'local',
        localPath: '/models/phi.gguf',
        checksum: _llmChecksum,
        enabled: true,
        installedAt: null,
        filePresent: true,
      );
      downloadService.existingPaths.add('/models/phi.gguf');
      downloadService.checksumMismatchPaths.add('/models/phi.gguf');

      final container = _modelProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          llmRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      await container.read(modelRegistryEntriesProvider.future);

      final states = await container.read(llmRuntimeStatesProvider.future);

      expect(states['llm-1']?.ready, isFalse);
      expect(states['llm-1']?.status, LlmRuntimeStatus.corrupted);
      expect(states['llm-1']?.reason, contains('校验失败'));
      expect(bridge.inspectCalls, 0);
    },
  );

  test(
    'startDownload marks task failed and skips registry write on checksum mismatch',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final bridge = _RecordingEmbeddingRuntimeBridge();
      final downloadService = _FakeDownloadService(
        error: StateError('Checksum mismatch for embed-2'),
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
              id: 'embed-2',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'MiniLM Embedding 2',
              description: '用于本地语义检索。',
              sizeBytes: 4096,
              minRamMb: 512,
              recommendedTier: 'mvp',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-2',
                  label: '镜像源',
                  url: 'https://example.com/embed-2.onnx',
                  checksum: 'sha256:expected-embed-2',
                ),
              ],
            ),
            source: const ModelSourceEntry(
              id: 'source-2',
              label: '镜像源',
              url: 'https://example.com/embed-2.onnx',
              checksum: 'sha256:expected-embed-2',
            ),
          );

      expect(bridge.ensureCalls, 0);
      expect(
        downloadRepository.tasksByModelAndSource('embed-2', 'source-2')?.status,
        ModelDownloadStatus.failed,
      );
      expect(
        downloadRepository
            .tasksByModelAndSource('embed-2', 'source-2')
            ?.errorMessage,
        contains('Checksum mismatch'),
      );
      expect(registryRepository.entries.containsKey('embed-2'), isFalse);
    },
  );

  test(
    'revalidateInstalledModel marks checksum-mismatched installed model as corrupted and disabled',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();

      // Registry entry with corrupted file (checksum mismatch)
      registryRepository.entries['embed-1'] = _trustedSingleArtifactEntry(
        id: 'embed-1',
        type: 'embedding',
        name: 'MiniLM Embedding',
        path: '/models/embed-1.onnx',
        quantization: 'Q8',
        enabled: true,
        integrityStatus: ModelIntegrityStatus.unknown,
      );
      downloadService.existingPaths.add('/models/embed-1.onnx');
      downloadService.checksumMismatchPaths.add('/models/embed-1.onnx');

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
          .revalidateInstalledModel('embed-1');

      // Should persist the corrupted state
      expect(registryRepository.entries['embed-1']?.filePresent, isTrue);
      expect(registryRepository.entries['embed-1']?.enabled, isFalse);
      expect(
        registryRepository.entries['embed-1']?.integrityStatus,
        ModelIntegrityStatus.corrupted,
      );
    },
  );

  test(
    'revalidateInstalledModel marks valid installed model as valid and enabled',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();

      registryRepository.entries['embed-1'] = _trustedSingleArtifactEntry(
        id: 'embed-1',
        type: 'embedding',
        name: 'MiniLM Embedding',
        path: '/models/embed-1.onnx',
        quantization: 'Q8',
        enabled: true,
        integrityStatus: ModelIntegrityStatus.unknown,
      );
      downloadService.existingPaths.add('/models/embed-1.onnx');
      // No checksumMismatchPaths entry → checksum passes

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
          .revalidateInstalledModel('embed-1');

      expect(registryRepository.entries['embed-1']?.filePresent, isTrue);
      expect(registryRepository.entries['embed-1']?.enabled, isTrue);
      expect(
        registryRepository.entries['embed-1']?.integrityStatus,
        ModelIntegrityStatus.valid,
      );
    },
  );

  test(
    'revalidateInstalledModel re-enables a recovered installed model after checksum passes',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final llmBridge = _RecordingLlmRuntimeBridge();

      registryRepository.entries['llm-1'] = _trustedSingleArtifactEntry(
        id: 'llm-1',
        type: 'llm',
        name: 'Qwen Local',
        path: '/models/qwen.gguf',
        quantization: 'Q4_K_M',
        enabled: false,
        integrityStatus: ModelIntegrityStatus.corrupted,
      );
      downloadService.existingPaths.add('/models/qwen.gguf');

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
          .revalidateInstalledModel('llm-1');

      expect(registryRepository.entries['llm-1']?.filePresent, isTrue);
      expect(registryRepository.entries['llm-1']?.enabled, isTrue);
      expect(
        registryRepository.entries['llm-1']?.integrityStatus,
        ModelIntegrityStatus.valid,
      );
      expect(llmBridge.ensureCalls, 1);
    },
  );

  test(
    'revalidateInstalledModel runs llm readiness probe and exposes ready runtime state',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final llmBridge = _RecordingLlmRuntimeBridge(
        ensureResult: <String, dynamic>{
          'ready': true,
          'status': 'ready',
          'reason': 'validated',
          'modelPath': '/models/qwen.gguf',
          'checkedAt': DateTime(2026, 4, 26).millisecondsSinceEpoch,
        },
      );

      registryRepository.entries['llm-1'] = _trustedSingleArtifactEntry(
        id: 'llm-1',
        type: 'llm',
        name: 'Qwen Local',
        path: '/models/qwen.gguf',
        quantization: 'Q4_K_M',
        enabled: false,
        integrityStatus: ModelIntegrityStatus.corrupted,
      );
      downloadService.existingPaths.add('/models/qwen.gguf');

      final container = _modelProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .revalidateInstalledModel('llm-1');
      final runtimeStates = await container.read(
        llmRuntimeStatesProvider.future,
      );

      expect(llmBridge.ensureCalls, greaterThanOrEqualTo(1));
      expect(llmBridge.lastModelId, 'llm-1');
      expect(llmBridge.lastModelPath, '/models/qwen.gguf');
      expect(runtimeStates['llm-1']?.ready, isTrue);
      expect(runtimeStates['llm-1']?.status, LlmRuntimeStatus.ready);
    },
  );
}
