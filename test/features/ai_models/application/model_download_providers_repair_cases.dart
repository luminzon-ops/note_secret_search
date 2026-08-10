part of 'model_download_providers_test.dart';

void _registerModelDownloadRepairCases() {
  test(
    'repairInstalledModel triggers fresh download for a broken installed model using catalog entry',
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
      final catalogRepository = _MemoryCatalogRepository(
        const <ModelCatalogEntry>[
          ModelCatalogEntry(
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
        ],
      );

      // Broken installed model (corrupted file)
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
        checksum: 'sha256:old-checksum',
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
          modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .repairInstalledModel('embed-1');

      // Should have triggered download via startDownload
      expect(downloadService.invocations, hasLength(1));
      expect(downloadService.invocations[0].modelId, 'embed-1');
      expect(
        downloadService.invocations[0].sourceUrl,
        'https://example.com/embed-1.onnx',
      );
      expect(downloadService.deletedPaths, contains('/models/embed-1.onnx'));
      expect(bridge.releasedModelIds, <String>['embed-1']);
      // After repair, model should be re-registered as valid
      expect(
        registryRepository.entries['embed-1']?.checksum,
        'sha256:verified-embed-1',
      );
      expect(
        registryRepository.entries['embed-1']?.integrityStatus,
        ModelIntegrityStatus.valid,
      );
    },
  );

  test(
    'repairInstalledModel safely handles missing catalog entry with no-op',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository();
      final downloadService = _FakeDownloadService();
      final catalogRepository = _MemoryCatalogRepository(
        const <ModelCatalogEntry>[],
      );

      registryRepository.entries['unknown-model'] = const ModelRegistryEntry(
        id: 'unknown-model',
        type: 'embedding',
        provider: 'builtin_catalog',
        name: 'Unknown',
        version: '1.0.0',
        sizeBytes: 4096,
        quantization: 'Q8',
        minRamMb: 512,
        recommendedTier: 'mvp',
        localPath: '/models/unknown.onnx',
        checksum: 'sha256:old-checksum',
        enabled: false,
        installedAt: null,
        filePresent: true,
        integrityStatus: ModelIntegrityStatus.corrupted,
      );
      downloadService.existingPaths.add('/models/unknown.onnx');

      final container = _modelProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
        ],
      );

      addTearDown(container.dispose);

      // Should not throw even though model has no catalog entry
      await container
          .read(modelDownloadControllerProvider)
          .repairInstalledModel('unknown-model');

      // No download should have been triggered
      expect(downloadService.invocations, isEmpty);
      // Registry entry remains unchanged (no crash)
      expect(registryRepository.entries['unknown-model']?.enabled, isFalse);
    },
  );
}
