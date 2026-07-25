part of 'model_download_providers.dart';

final modelDownloadRepositoryProvider = Provider<ModelDownloadRepository>((
  ref,
) {
  return SqliteModelDownloadRepository(
    database: ref.watch(appDatabaseProvider),
  );
});

final modelRegistryRepositoryProvider = Provider<ModelRegistryRepository>((
  ref,
) {
  return SqliteModelRegistryRepository(
    database: ref.watch(appDatabaseProvider),
    beforeMutation: ref.watch(searchIndexWriteFenceProvider).invalidate,
  );
});

final modelLifecycleStoreProvider = Provider<ModelLifecycleStore>((ref) {
  return SqliteModelLifecycleStore(
    database: ref.watch(appDatabaseProvider),
    beforeMutation: ref.watch(searchIndexWriteFenceProvider).invalidate,
  );
});

final modelArtifactStoreProvider = Provider<ModelArtifactStore>((ref) {
  return IoModelArtifactStore();
});

final modelRevisionStoreProvider = Provider<ModelRevisionStore>((ref) {
  return IoModelRevisionStore();
});

final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  return ModelDownloadService(dio: Dio(), logger: ref.watch(loggerProvider));
});

final modelSourceProbeServiceProvider = Provider<ModelSourceProbeService>((
  ref,
) {
  return ModelSourceProbeService(dio: Dio(), logger: ref.watch(loggerProvider));
});

final modelDownloadControllerProvider = Provider<ModelDownloadController>((
  ref,
) {
  return ModelDownloadController(
    ref: ref,
    repository: ref.watch(modelDownloadRepositoryProvider),
    registryRepository: ref.watch(modelRegistryRepositoryProvider),
    downloadService: ref.watch(modelDownloadServiceProvider),
    lifecycleStore: ref.watch(modelLifecycleStoreProvider),
    artifactStore: ref.watch(modelArtifactStoreProvider),
    revisionStore: ref.watch(modelRevisionStoreProvider),
    logger: ref.watch(loggerProvider),
  );
});
