part of 'model_download_providers.dart';

final modelDownloadRepositoryProvider = Provider<ModelDownloadRepository>((
  ref,
) {
  throw StateError(
    'modelDownloadRepositoryProvider must be overridden by app composition',
  );
});

final modelRegistryRepositoryProvider = Provider<ModelRegistryRepository>((
  ref,
) {
  throw StateError(
    'modelRegistryRepositoryProvider must be overridden by app composition',
  );
});

final modelLifecycleStoreProvider = Provider<ModelLifecycleStore>((ref) {
  throw StateError(
    'modelLifecycleStoreProvider must be overridden by app composition',
  );
});

final modelArtifactStoreProvider = Provider<ModelArtifactStore>((ref) {
  throw StateError(
    'modelArtifactStoreProvider must be overridden by app composition',
  );
});

final modelRevisionStoreProvider = Provider<ModelRevisionStore>((ref) {
  throw StateError(
    'modelRevisionStoreProvider must be overridden by app composition',
  );
});

final bundledModelArtifactStagerProvider = Provider<BundledModelArtifactStager>((
  ref,
) {
  throw StateError(
    'bundledModelArtifactStagerProvider must be overridden by app composition',
  );
});

final modelDownloadServiceProvider = Provider<ModelDownloadGateway>((ref) {
  throw StateError(
    'modelDownloadServiceProvider must be overridden by app composition',
  );
});

final modelSourceProbeServiceProvider = Provider<ModelSourceProbe>((ref) {
  throw StateError(
    'modelSourceProbeServiceProvider must be overridden by app composition',
  );
});

final modelDownloadControllerProvider = Provider<ModelDownloadController>((
  ref,
) {
  return ModelDownloadController(
    repository: ref.watch(modelDownloadRepositoryProvider),
    registryRepository: ref.watch(modelRegistryRepositoryProvider),
    downloadService: ref.watch(modelDownloadServiceProvider),
    lifecycleStore: ref.watch(modelLifecycleStoreProvider),
    artifactStore: ref.watch(modelArtifactStoreProvider),
    revisionStore: ref.watch(modelRevisionStoreProvider),
    bundledArtifactStager: ref.watch(bundledModelArtifactStagerProvider),
    runtimeCoordinator: ref.watch(modelRuntimeCoordinatorProvider),
    sourceProbe: ref.watch(modelSourceProbeServiceProvider),
    loadRegistryEntries: () => ref.read(modelRegistryEntriesProvider.future),
    loadCatalogEntries: () => ref.read(modelCatalogEntriesProvider.future),
    invalidateDownloadTasks: () => ref.invalidate(modelDownloadTasksProvider),
    invalidateRegistryEntries: () =>
        ref.invalidate(modelRegistryEntriesProvider),
    invalidateEmbeddingRuntimeStates: () =>
        ref.invalidate(embeddingRuntimeStatesProvider),
    logger: ref.watch(loggerProvider),
  );
});
