part of 'model_download_providers_test.dart';

class _MemoryDownloadRepository implements ModelDownloadRepository {
  final Map<String, ModelDownloadTask> tasksById =
      <String, ModelDownloadTask>{};

  ModelDownloadTask? tasksByModelAndSource(String modelId, String sourceId) {
    for (final task in tasksById.values) {
      if (task.modelId == modelId && task.sourceId == sourceId) {
        return task;
      }
    }
    return null;
  }

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async {
    for (final task in tasksById.values) {
      if (task.modelId == modelId) {
        return task;
      }
    }
    return null;
  }

  @override
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(
    String modelId,
    String sourceId,
  ) async {
    return tasksByModelAndSource(modelId, sourceId);
  }

  @override
  Future<List<ModelDownloadTask>> listTasks() async =>
      tasksById.values.toList(growable: false);

  @override
  Future<void> saveTask(ModelDownloadTask task) async {
    tasksById[task.id] = task;
  }
}

class _MemoryRegistryRepository implements ModelRegistryRepository {
  final Map<String, ModelRegistryEntry> entries =
      <String, ModelRegistryEntry>{};

  @override
  Future<void> deleteById(String id) async {
    entries.remove(id);
  }

  @override
  Future<ModelRegistryEntry?> getById(String id) async => entries[id];

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async =>
      entries.values.toList(growable: false);

  @override
  Future<void> save(ModelRegistryEntry entry) async {
    entries[entry.id] = entry;
  }
}

class _MemoryCatalogAcceptanceStore implements ModelCatalogAcceptanceStore {
  ModelCatalogAcceptanceState? state;

  @override
  Future<ModelCatalogAcceptanceState?> read() async => state;

  @override
  Future<void> accept(ModelCatalogAcceptanceState state) async {
    this.state = state;
  }
}

class _MemoryCatalogRepository implements ModelCatalogRepository {
  _MemoryCatalogRepository(this.entries);

  final List<ModelCatalogEntry> entries;

  @override
  Future<List<ModelCatalogEntry>> loadCatalog() async => entries;
}

class _FakeDownloadService extends ModelDownloadService {
  _FakeDownloadService({this.result, this.error})
    : super(dio: Dio(), logger: const AppLogger());

  final ModelDownloadResult? result;
  final Object? error;
  final Set<String> existingPaths = <String>{};
  final Map<String, int> fileLengths = <String, int>{};
  final Set<String> checksumMismatchPaths = <String>{};
  final Map<String, ModelDownloadResult> resultsBySourceUrl =
      <String, ModelDownloadResult>{};
  final Map<String, Object> errorsBySourceUrl = <String, Object>{};
  final Map<String, ModelDownloadTarget> targetsByKey =
      <String, ModelDownloadTarget>{};
  final List<String> inspectedKeys = <String>[];
  final List<_DownloadInvocation> invocations = <_DownloadInvocation>[];
  final List<String> deletedPaths = <String>[];
  final List<String?> fileExistsPaths = <String?>[];
  final List<String> verifiedPaths = <String>[];
  final Set<String> checksumProbeFailurePaths = <String>{};
  Completer<void>? progressGate;
  int? lastResumeFromBytes;
  String? lastTaskId;
  String? lastModelId;
  String? lastSourceUrl;

  String _targetKey(String modelId, String sourceUrl) => '$modelId|$sourceUrl';

  void setTarget({
    required String modelId,
    required String sourceUrl,
    required int existingBytes,
    String? localPath,
  }) {
    targetsByKey[_targetKey(modelId, sourceUrl)] = ModelDownloadTarget(
      localPath: localPath ?? '/partials/$modelId.partial',
      exists: existingBytes > 0,
      existingBytes: existingBytes,
    );
  }

  void setResultForSource({
    required String sourceUrl,
    required ModelDownloadResult result,
  }) {
    resultsBySourceUrl[sourceUrl] = result;
  }

  void setErrorForSource({required String sourceUrl, required Object error}) {
    errorsBySourceUrl[sourceUrl] = error;
  }

  @override
  Future<ModelDownloadResult> download({
    required String taskId,
    required String modelId,
    required String sourceUrl,
    required String expectedChecksum,
    int resumeFromBytes = 0,
    required void Function(ModelDownloadProgress progress) onProgress,
  }) async {
    lastTaskId = taskId;
    lastModelId = modelId;
    lastSourceUrl = sourceUrl;
    lastResumeFromBytes = resumeFromBytes;
    invocations.add(
      _DownloadInvocation(
        taskId: taskId,
        modelId: modelId,
        sourceUrl: sourceUrl,
        resumeFromBytes: resumeFromBytes,
      ),
    );

    final sourceError = errorsBySourceUrl[sourceUrl];
    if (sourceError != null) {
      throw sourceError;
    }

    if (error != null) {
      throw error!;
    }

    final resolvedResult = resultsBySourceUrl[sourceUrl] ?? result!;
    if (progressGate != null) {
      await progressGate!.future;
    }
    onProgress(
      ModelDownloadProgress(
        receivedBytes: resolvedResult.totalBytes,
        totalBytes: resolvedResult.totalBytes,
        averageSpeedBytesPerSecond: 1024,
      ),
    );
    return resolvedResult;
  }

  @override
  Future<ModelDownloadTarget> inspectDownloadTarget({
    required String modelId,
    required String sourceUrl,
  }) async {
    final key = _targetKey(modelId, sourceUrl);
    inspectedKeys.add(key);
    return targetsByKey[key] ??
        ModelDownloadTarget(
          localPath: '/partials/$modelId.partial',
          exists: false,
          existingBytes: 0,
        );
  }

  @override
  Future<bool> fileExists(String? path) async {
    fileExistsPaths.add(path);
    return path != null &&
        (existingPaths.contains(path) || path == result?.localPath);
  }

  @override
  Future<int?> fileLength(String? path) async {
    if (path == null || !await fileExists(path)) {
      return null;
    }
    return fileLengths[path] ?? 4096;
  }

  @override
  Future<String> verifyChecksum({
    required String filePath,
    required String expectedChecksum,
  }) async {
    verifiedPaths.add(filePath);
    if (checksumProbeFailurePaths.contains(filePath)) {
      throw StateError('Unexpected checksum probe for $filePath');
    }
    if (checksumMismatchPaths.contains(filePath)) {
      throw StateError('Checksum mismatch for $filePath');
    }
    return expectedChecksum;
  }

  @override
  Future<void> deleteLocalFile(String? path) async {
    if (path == null) {
      return;
    }
    deletedPaths.add(path);
  }
}

class _DownloadInvocation {
  const _DownloadInvocation({
    required this.taskId,
    required this.modelId,
    required this.sourceUrl,
    required this.resumeFromBytes,
  });

  final String taskId;
  final String modelId;
  final String sourceUrl;
  final int resumeFromBytes;
}

class _FakeModelSourceProbeService extends ModelSourceProbeService {
  _FakeModelSourceProbeService() : super(dio: Dio(), logger: const AppLogger());

  final Map<String, ModelSourceProbeResult> resultsBySourceId =
      <String, ModelSourceProbeResult>{};

  void setResult(ModelSourceProbeResult result) {
    resultsBySourceId[result.sourceId] = result;
  }

  @override
  Future<ModelSourceProbeResult> probeSource({
    required ModelSourceEntry source,
    int? expectedSizeBytes,
  }) async {
    return resultsBySourceId[source.id] ??
        ModelSourceProbeResult(
          sourceId: source.id,
          reachable: true,
          statusCode: 200,
          contentLength: expectedSizeBytes,
          rangeSupported: false,
          latencyMs: 100,
          usedFallbackRangeProbe: false,
        );
  }
}

class _RecordingEmbeddingRuntimeBridge implements EmbeddingRuntimeBridge {
  int inspectCalls = 0;
  int ensureCalls = 0;
  String? lastModelId;
  String? lastModelPath;
  String? lastVerifiedChecksum;
  EmbeddingTokenizerSpec? lastTokenizer;
  EmbeddingRuntimeSpec? lastRuntime;
  final List<String> releasedModelIds = <String>[];

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
    ensureCalls++;
    lastModelId = modelId;
    lastModelPath = modelPath;
    lastVerifiedChecksum = verifiedChecksum;
    lastTokenizer = tokenizer;
    lastRuntime = runtime;
    return <String, dynamic>{
      'status': 'ready',
      'reason': 'validated',
      'modelPath': modelPath,
      'checkedAt': DateTime(2026, 4, 26).millisecondsSinceEpoch,
      'vectorDimension': 384,
    };
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) async {
    inspectCalls++;
    return <String, dynamic>{
      'status': 'installedUnverified',
      'reason': 'pending',
      'modelPath': modelPath,
    };
  }

  @override
  Future<void> cancelRequest({required String requestId}) async {}

  @override
  Future<void> releaseModel({required String modelId}) async {
    releasedModelIds.add(modelId);
  }
}

class _RecordingLlmRuntimeBridge implements LlmRuntimeBridge {
  _RecordingLlmRuntimeBridge({this.ensureResult});

  int inspectCalls = 0;
  int ensureCalls = 0;
  String? lastModelId;
  String? lastModelPath;
  final Map<String, dynamic>? ensureResult;
  final Set<String> readyModelIds = <String>{};

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  }) async {
    ensureCalls++;
    lastModelId = modelId;
    lastModelPath = modelPath;
    final result =
        ensureResult ??
        <String, dynamic>{
          'ready': true,
          'status': 'ready',
          'reason': 'validated',
          'modelPath': modelPath,
          'checkedAt': DateTime(2026, 4, 26).millisecondsSinceEpoch,
        };
    if (result['status'] == 'ready' || result['ready'] == true) {
      readyModelIds.add(modelId);
    } else {
      readyModelIds.remove(modelId);
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> generateText({
    required String modelId,
    required String modelPath,
    required String prompt,
    required bool usedPrivateContext,
    required int maxOutputTokens,
    required int maxPromptChars,
    required int contextLength,
    required bool conservativeMode,
    required double temperature,
    required int topK,
    required double topP,
    required int seed,
    required List<String> stopSequences,
    required bool emitPartialCompletion,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  }) async {
    inspectCalls++;
    if (readyModelIds.contains(modelId)) {
      return <String, dynamic>{
        'ready': true,
        'status': 'ready',
        'reason': 'validated',
        'modelPath': modelPath,
      };
    }
    return <String, dynamic>{
      'ready': false,
      'status': 'installed_unverified',
      'reason': 'pending',
      'modelPath': modelPath,
    };
  }

  @override
  Future<void> releaseModel({required String modelId}) async {}
}

class _RecordingMultimodalLlmRuntimeBridge
    implements MultimodalLlmRuntimeBridge {
  _RecordingMultimodalLlmRuntimeBridge({required this.ensureResult});

  final Map<String, dynamic> ensureResult;
  int ensureCalls = 0;
  String? lastModelId;
  String? lastModelPath;
  String? lastMmprojPath;

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    required String mmprojPath,
  }) async {
    ensureCalls++;
    lastModelId = modelId;
    lastModelPath = modelPath;
    lastMmprojPath = mmprojPath;
    return ensureResult;
  }

  @override
  Future<Map<String, dynamic>> generateMultimodalText({
    required String modelId,
    required String modelPath,
    required String mmprojPath,
    required String imagePath,
    required String prompt,
    required int maxOutputTokens,
    required int contextLength,
    required bool reasoningEnabled,
  }) {
    throw UnimplementedError();
  }
}
