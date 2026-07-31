part of 'model_management_page_test.dart';

class _FakeModelDownloadRepository implements ModelDownloadRepository {
  const _FakeModelDownloadRepository();

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async =>
      null;

  @override
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(
    String modelId,
    String sourceId,
  ) async => null;

  @override
  Future<List<ModelDownloadTask>> listTasks() async =>
      const <ModelDownloadTask>[];

  @override
  Future<void> saveTask(ModelDownloadTask task) async {}
}

class _FakeModelRegistryRepository implements ModelRegistryRepository {
  const _FakeModelRegistryRepository();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<ModelRegistryEntry?> getById(String id) async => null;

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async =>
      const <ModelRegistryEntry>[];

  @override
  Future<void> save(ModelRegistryEntry entry) async {}
}

class _FakeModelLifecycleStore implements ModelLifecycleStore {
  const _FakeModelLifecycleStore();

  @override
  Future<void> commitInstallation({
    required ModelRegistryEntry registryEntry,
    required List<ModelDownloadTask> completedTasks,
  }) async {}

  @override
  Future<ModelRegistryEntry?> getDeletionManifest(String modelId) async => null;

  @override
  Future<void> purgeModelData(String modelId) async {}
}

class _FakeModelArtifactStore implements ModelArtifactStore {
  const _FakeModelArtifactStore();

  @override
  Future<void> deleteModelArtifacts({
    required String modelId,
    required String? primaryPath,
    required List<ModelArtifactPath> artifacts,
  }) async {}
}

class _FakeModelDownloadController extends ModelDownloadController {
  _FakeModelDownloadController({required Ref ref})
    : super(
        repository: const _FakeModelDownloadRepository(),
        registryRepository: const _FakeModelRegistryRepository(),
        downloadService: ModelDownloadService(
          dio: Dio(),
          logger: const AppLogger(),
        ),
        lifecycleStore: const _FakeModelLifecycleStore(),
        artifactStore: const _FakeModelArtifactStore(),
        logger: const AppLogger(),
      );
}

class _RecordingModelDownloadController extends _FakeModelDownloadController {
  _RecordingModelDownloadController({required super.ref});

  ModelCatalogEntry? startedEntry;
  ModelSourceEntry? startedSource;
  String? revalidatedModelId;
  String? repairedModelId;
  String? deletedModelId;

  @override
  Future<void> startDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
  }) async {
    startedEntry = entry;
    startedSource = source;
  }

  @override
  Future<void> revalidateInstalledModel(String modelId) async {
    revalidatedModelId = modelId;
  }

  @override
  Future<void> repairInstalledModel(String modelId) async {
    repairedModelId = modelId;
  }

  @override
  Future<void> deleteInstalledModel(String modelId) async {
    deletedModelId = modelId;
  }
}
