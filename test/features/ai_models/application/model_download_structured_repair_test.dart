part of 'model_download_structured_integration_test.dart';

void _registerStructuredRepairTests() {
  test(
    'repair reuses healthy model bytes and downloads only corrupt sidecar',
    () async {
      final downloads = _HistoryDownloadRepository();
      final registry = _MemoryRegistryRepository()
        ..entry = _repairRegistryEntry;
      final lifecycle = _RecordingLifecycleStore(
        downloads: downloads,
        registry: registry,
      );
      final service = _RepairIntegrityDownloadService();
      final revisions = _RecordingRevisionStore();
      final bridge = _ReadyEmbeddingBridge();
      final container = ProviderContainer(
        overrides: <Override>[
          modelDownloadRepositoryProvider.overrideWithValue(downloads),
          modelRegistryRepositoryProvider.overrideWithValue(registry),
          modelLifecycleStoreProvider.overrideWithValue(lifecycle),
          modelDownloadServiceProvider.overrideWithValue(service),
          modelRevisionStoreProvider.overrideWithValue(revisions),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const <ModelCatalogEntry>[_entry],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(modelDownloadControllerProvider)
          .repairInstalledModel('structured-model');

      expect(revisions.reusedArtifactIds, <String>['model']);
      expect(service.calls.map((call) => call.artifactId), <String>['sidecar']);
      expect(
        revisions.artifacts.map((artifact) => artifact.artifactId),
        <String>['model', 'sidecar'],
      );
      expect(registry.entry?.generation, 2);
      expect(registry.entry?.integrityStatus, ModelIntegrityStatus.valid);
      expect(registry.entry?.isInstalled, isTrue);
      expect(
        lifecycle.journals
            .where((journal) => journal.operationType == 'repair')
            .map((journal) => journal.phase),
        <String>[
          'queued',
          'staging',
          'staged',
          'runtime_validating',
          'releasing_sessions',
          'installing',
          'committing',
          'completed',
        ],
      );
    },
  );
}

const _repairRegistryEntry = ModelRegistryEntry(
  id: 'structured-model',
  type: 'embedding',
  provider: 'builtin_catalog',
  name: 'Structured Model',
  version: 'release-1',
  sizeBytes: 12,
  quantization: null,
  minRamMb: 512,
  recommendedTier: 'local',
  localPath: '/support/models/structured-model/revisions/1/runtime/model.onnx',
  checksum: _modelDigest,
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
  releaseId: 'release-1',
  catalogVersion: 7,
  catalogDigest:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  generation: 1,
  revisionRoot: 'revisions/1',
  artifacts: <ModelArtifactPath>[
    ModelArtifactPath(
      artifactId: 'model',
      releaseId: 'release-1',
      role: 'model',
      sourceId: 'model-source',
      localPath:
          '/support/models/structured-model/revisions/1/runtime/model.onnx',
      relativePath: 'runtime/model.onnx',
      required: true,
      expectedChecksum: _modelDigest,
      verifiedChecksum: _modelDigest,
      expectedSizeBytes: 10,
      verifiedSizeBytes: 10,
      state: 'installed',
      verifiedAt: 1,
    ),
    ModelArtifactPath(
      artifactId: 'sidecar',
      releaseId: 'release-1',
      role: 'sidecar',
      sourceId: 'sidecar-source',
      localPath:
          '/support/models/structured-model/revisions/1/runtime/sidecar.json',
      relativePath: 'runtime/sidecar.json',
      required: true,
      expectedChecksum: _sidecarDigest,
      verifiedChecksum: _sidecarDigest,
      expectedSizeBytes: 2,
      verifiedSizeBytes: 2,
      state: 'installed',
      verifiedAt: 1,
    ),
  ],
);

class _RepairIntegrityDownloadService
    extends _ScriptedStructuredDownloadService {
  static const _modelPath =
      '/support/models/structured-model/revisions/1/runtime/model.onnx';
  static const _sidecarPath =
      '/support/models/structured-model/revisions/1/runtime/sidecar.json';

  @override
  Future<bool> fileExists(String? path) async {
    return path == _modelPath || path == _sidecarPath;
  }

  @override
  Future<int?> fileLength(String? path) async {
    return switch (path) {
      _modelPath => 10,
      _sidecarPath => 2,
      _ => null,
    };
  }

  @override
  Future<String> verifyChecksum({
    required String filePath,
    required String expectedChecksum,
  }) async {
    if (filePath == _sidecarPath) {
      throw StateError('Checksum mismatch for sidecar');
    }
    return expectedChecksum;
  }
}
