part of 'model_download_providers_test.dart';

const _embeddingChecksum =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _qwenChecksum =
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _llmChecksum =
    'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

ProviderContainer _modelProviderContainer({required List<Override> overrides}) {
  return ProviderContainer(
    overrides: <Override>[
      ...modelRuntimeFixtureOverrides(),
      modelCatalogAcceptanceStoreProvider.overrideWith(
        (ref) => _MemoryCatalogAcceptanceStore(),
      ),
      modelCatalogRepositoryProvider.overrideWith(
        (ref) => _MemoryCatalogRepository(const <ModelCatalogEntry>[]),
      ),
      modelDownloadRepositoryProvider.overrideWith(
        (ref) => _MemoryDownloadRepository(),
      ),
      modelRegistryRepositoryProvider.overrideWith(
        (ref) => _MemoryRegistryRepository(),
      ),
      modelSourceProbeServiceProvider.overrideWith(
        (ref) => _FakeModelSourceProbeService(),
      ),
      modelLifecycleStoreProvider.overrideWith((ref) {
        return _RepositoryBackedTestLifecycleStore(
          downloadRepository: ref.watch(modelDownloadRepositoryProvider),
          registryRepository: ref.watch(modelRegistryRepositoryProvider),
        );
      }),
      ...overrides,
    ],
  );
}

class _RepositoryBackedTestLifecycleStore implements ModelLifecycleStore {
  const _RepositoryBackedTestLifecycleStore({
    required ModelDownloadRepository downloadRepository,
    required ModelRegistryRepository registryRepository,
  }) : _downloadRepository = downloadRepository,
       _registryRepository = registryRepository;

  final ModelDownloadRepository _downloadRepository;
  final ModelRegistryRepository _registryRepository;

  @override
  Future<void> commitInstallation({
    required ModelRegistryEntry registryEntry,
    required List<ModelDownloadTask> completedTasks,
  }) async {
    await _registryRepository.save(registryEntry);
    for (final task in completedTasks) {
      await _downloadRepository.saveTask(task);
    }
  }

  @override
  Future<ModelRegistryEntry?> getDeletionManifest(String modelId) {
    return _registryRepository.getById(modelId);
  }

  @override
  Future<void> purgeModelData(String modelId) async {
    final downloadRepository = _downloadRepository;
    if (downloadRepository is _MemoryDownloadRepository) {
      downloadRepository.tasksById.removeWhere(
        (_, task) => task.modelId == modelId,
      );
    }
    await _registryRepository.deleteById(modelId);
  }
}

ModelDownloadTask _buildTask({
  required String id,
  required String modelId,
  required String sourceId,
  required ModelDownloadStatus status,
  int downloadedBytes = 0,
}) {
  return ModelDownloadTask(
    id: id,
    modelId: modelId,
    sourceId: sourceId,
    status: status,
    totalBytes: 4096,
    downloadedBytes: downloadedBytes,
    averageSpeed: null,
    errorMessage: null,
    resumable: true,
    createdAt: DateTime(2026, 4, 26, 10, 0),
    updatedAt: DateTime(2026, 4, 26, 10, 1),
  );
}

ModelRegistryEntry _trustedSingleArtifactEntry({
  required String id,
  required String type,
  required String name,
  required String path,
  required String quantization,
  required bool enabled,
  required ModelIntegrityStatus integrityStatus,
}) {
  final checksum = 'sha256:${'a' * 64}';
  return ModelRegistryEntry(
    id: id,
    type: type,
    provider: 'builtin_catalog',
    name: name,
    version: 'release-1',
    sizeBytes: 4096,
    quantization: quantization,
    minRamMb: type == 'llm' ? 2048 : 512,
    recommendedTier: type == 'llm' ? 'local' : 'mvp',
    localPath: path,
    checksum: checksum,
    enabled: enabled,
    installedAt: null,
    filePresent: true,
    integrityStatus: integrityStatus,
    releaseId: 'release-1',
    catalogVersion: 7,
    catalogDigest:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    generation: 1,
    revisionRoot: 'revisions/1',
    artifacts: <ModelArtifactPath>[
      ModelArtifactPath(
        artifactId: 'model',
        releaseId: 'release-1',
        role: 'model',
        sourceId: 'source-1',
        localPath: path,
        relativePath: 'runtime/model.bin',
        required: true,
        expectedChecksum: checksum,
        verifiedChecksum: checksum,
        expectedSizeBytes: 4096,
        verifiedSizeBytes: 4096,
        state: 'installed',
        verifiedAt: 1,
      ),
    ],
  );
}
