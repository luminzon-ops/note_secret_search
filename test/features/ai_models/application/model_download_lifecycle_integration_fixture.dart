part of 'model_download_lifecycle_integration_test.dart';

class _MemoryDownloadRepository implements ModelDownloadRepository {
  ModelDownloadTask? latest;

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async {
    return latest?.modelId == modelId ? latest : null;
  }

  @override
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(
    String modelId,
    String sourceId,
  ) async {
    final task = latest;
    return task?.modelId == modelId && task?.sourceId == sourceId ? task : null;
  }

  @override
  Future<List<ModelDownloadTask>> listTasks() async {
    return latest == null
        ? const <ModelDownloadTask>[]
        : <ModelDownloadTask>[latest!];
  }

  @override
  Future<void> saveTask(ModelDownloadTask task) async {
    latest = task;
  }
}

class _MemoryRegistryRepository implements ModelRegistryRepository {
  ModelRegistryEntry? entry;

  @override
  Future<void> deleteById(String id) async {
    if (entry?.id == id) {
      entry = null;
    }
  }

  @override
  Future<ModelRegistryEntry?> getById(String id) async {
    return entry?.id == id ? entry : null;
  }

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async {
    return entry == null
        ? const <ModelRegistryEntry>[]
        : <ModelRegistryEntry>[entry!];
  }

  @override
  Future<void> save(ModelRegistryEntry entry) async {
    this.entry = entry;
  }
}

class _RecordingLifecycleStore implements ModelLifecycleStore {
  _RecordingLifecycleStore({
    required this.downloadRepository,
    required this.registryRepository,
  });

  final _MemoryDownloadRepository downloadRepository;
  final _MemoryRegistryRepository registryRepository;
  int commitCalls = 0;

  @override
  Future<void> commitInstallation({
    required ModelRegistryEntry registryEntry,
    required List<ModelDownloadTask> completedTasks,
  }) async {
    commitCalls += 1;
    await registryRepository.save(registryEntry);
    for (final task in completedTasks) {
      await downloadRepository.saveTask(task);
    }
  }

  @override
  Future<ModelRegistryEntry?> getDeletionManifest(String modelId) {
    return registryRepository.getById(modelId);
  }

  @override
  Future<void> purgeModelData(String modelId) async {
    await registryRepository.deleteById(modelId);
  }
}

class _SuccessfulDownloadService extends ModelDownloadService {
  _SuccessfulDownloadService() : super(dio: Dio(), logger: const AppLogger());

  bool downloaded = false;

  @override
  Future<ModelDownloadResult> download({
    required String taskId,
    required String modelId,
    required String sourceUrl,
    required String expectedChecksum,
    int resumeFromBytes = 0,
    required FutureOr<void> Function(ModelDownloadProgress progress) onProgress,
  }) async {
    downloaded = true;
    await onProgress(
      const ModelDownloadProgress(
        receivedBytes: 10,
        totalBytes: 10,
        averageSpeedBytesPerSecond: 10,
      ),
    );
    return const ModelDownloadResult(
      localPath: '/support/models/model-1/model.onnx',
      totalBytes: 10,
      verifiedChecksum: 'sha256:model',
    );
  }

  @override
  Future<bool> fileExists(String? path) async {
    return downloaded && path == '/support/models/model-1/model.onnx';
  }

  @override
  Future<ModelDownloadTarget> inspectDownloadTarget({
    required String modelId,
    required String sourceUrl,
  }) async {
    return ModelDownloadTarget(
      localPath: '/support/models/model-1/model.onnx',
      exists: downloaded,
      existingBytes: downloaded ? 10 : 0,
    );
  }

  @override
  Future<String> verifyChecksum({
    required String filePath,
    required String expectedChecksum,
  }) async {
    return 'sha256:model';
  }
}

class _ThrowingEmbeddingRuntimeBridge implements EmbeddingRuntimeBridge {
  const _ThrowingEmbeddingRuntimeBridge();

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) {
    throw StateError('runtime_failed');
  }

  @override
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
    String? requestId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelRequest({required String requestId}) async {}

  @override
  Future<void> releaseModel({required String modelId}) async {}
}

class _RecordingEmbeddingRuntimeBridge implements EmbeddingRuntimeBridge {
  _RecordingEmbeddingRuntimeBridge({required this.onRelease});

  final FutureOr<void> Function(String modelId) onRelease;
  final List<String> releasedModelIds = <String>[];

  @override
  Future<void> cancelRequest({required String requestId}) async {}

  @override
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
    String? requestId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) async {
    return <String, dynamic>{
      'ready': true,
      'status': 'ready',
      'reason': 'validated',
      'modelPath': modelPath,
    };
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> releaseModel({required String modelId}) async {
    releasedModelIds.add(modelId);
    await onRelease(modelId);
  }
}

class _NoopArtifactStore implements ModelArtifactStore {
  const _NoopArtifactStore();

  @override
  Future<void> deleteModelArtifacts({
    required String modelId,
    required String? primaryPath,
    required List<ModelArtifactPath> artifacts,
  }) async {}
}
