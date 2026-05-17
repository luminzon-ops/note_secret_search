import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_source_probe_service.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/multimodal_llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';

class _MemoryDownloadRepository implements ModelDownloadRepository {
  final Map<String, ModelDownloadTask> tasksById = <String, ModelDownloadTask>{};

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
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(String modelId, String sourceId) async {
    return tasksByModelAndSource(modelId, sourceId);
  }

  @override
  Future<List<ModelDownloadTask>> listTasks() async => tasksById.values.toList(growable: false);

  @override
  Future<void> saveTask(ModelDownloadTask task) async {
    tasksById[task.id] = task;
  }
}

class _MemoryRegistryRepository implements ModelRegistryRepository {
  final Map<String, ModelRegistryEntry> entries = <String, ModelRegistryEntry>{};

  @override
  Future<void> deleteById(String id) async {
    entries.remove(id);
  }

  @override
  Future<ModelRegistryEntry?> getById(String id) async => entries[id];

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async => entries.values.toList(growable: false);

  @override
  Future<void> save(ModelRegistryEntry entry) async {
    entries[entry.id] = entry;
  }
}

class _MemoryCatalogRepository implements ModelCatalogRepository {
  _MemoryCatalogRepository(this.entries);

  final List<ModelCatalogEntry> entries;

  @override
  Future<List<ModelCatalogEntry>> loadCatalog() async => entries;
}

class _FakeDownloadService extends ModelDownloadService {
  _FakeDownloadService({this.result, this.error}) : super(dio: Dio(), logger: const AppLogger());

  final ModelDownloadResult? result;
  final Object? error;
  final Set<String> existingPaths = <String>{};
  final Set<String> checksumMismatchPaths = <String>{};
  final Map<String, ModelDownloadResult> resultsBySourceUrl = <String, ModelDownloadResult>{};
  final Map<String, Object> errorsBySourceUrl = <String, Object>{};
  final Map<String, ModelDownloadTarget> targetsByKey = <String, ModelDownloadTarget>{};
  final List<String> inspectedKeys = <String>[];
  final List<_DownloadInvocation> invocations = <_DownloadInvocation>[];
  final List<String> deletedPaths = <String>[];
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

  void setErrorForSource({
    required String sourceUrl,
    required Object error,
  }) {
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
  Future<bool> fileExists(String? path) async =>
      path != null && (existingPaths.contains(path) || path == result?.localPath);

  @override
  Future<String> verifyChecksum({
    required String filePath,
    required String expectedChecksum,
  }) async {
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

  final Map<String, ModelSourceProbeResult> resultsBySourceId = <String, ModelSourceProbeResult>{};

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
  EmbeddingTokenizerSpec? lastTokenizer;
  EmbeddingRuntimeSpec? lastRuntime;

  @override
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) async {
    ensureCalls++;
    lastModelId = modelId;
    lastModelPath = modelPath;
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
  }) async {
    inspectCalls++;
    return <String, dynamic>{
      'status': 'installedUnverified',
      'reason': 'pending',
      'modelPath': modelPath,
    };
  }

  @override
  Future<void> releaseModel({required String modelId}) async {}
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
  Future<Map<String, dynamic>> ensureModelReady({required String modelId, required String modelPath}) async {
    ensureCalls++;
    lastModelId = modelId;
    lastModelPath = modelPath;
    final result = ensureResult ?? <String, dynamic>{
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> inspectModel({required String modelId, required String modelPath}) async {
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

class _RecordingMultimodalLlmRuntimeBridge implements MultimodalLlmRuntimeBridge {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ModelDownloadTask buildTask({
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

  test('startDownload validates embedding runtime after download completes', () async {
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

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
          entry: const ModelCatalogEntry(
            id: 'embed-1',
            type: 'embedding',
            tier: 'mvp',
            displayName: 'MiniLM Embedding',
            description: '用于本地语义检索。',
            sizeBytes: 4096,
            minRamMb: 512,
            recommendedTier: 'mvp',
            tokenizer: EmbeddingTokenizerSpec(
              format: 'tokenizer_json',
              assetPath: 'assets/model_catalog/tokenizers/all_minilm/tokenizer.json',
              maxSequenceLength: 256,
              lowercase: true,
            ),
            runtime: EmbeddingRuntimeSpec(
              inputIdsName: 'input_ids',
              attentionMaskName: 'attention_mask',
              outputName: 'last_hidden_state',
              pooling: 'mean',
              normalization: 'l2',
            ),
            sources: <ModelSourceEntry>[
              ModelSourceEntry(
                id: 'source-1',
                label: '镜像源',
                url: 'https://example.com/embed-1.onnx',
                checksum: 'sha256:verified-embed-1',
              ),
            ],
          ),
           source: const ModelSourceEntry(
             id: 'source-1',
             label: '镜像源',
             url: 'https://example.com/embed-1.onnx',
             checksum: 'sha256:verified-embed-1',
           ),
         );

    expect(bridge.ensureCalls, 1);
    expect(bridge.lastModelId, 'embed-1');
    expect(bridge.lastModelPath, '/models/embed-1.onnx');
    expect(bridge.lastTokenizer, isNotNull);
    expect(bridge.lastTokenizer?.maxSequenceLength, 256);
    expect(bridge.lastRuntime, isNotNull);
    expect(bridge.lastRuntime?.pooling, 'mean');
    expect(registryRepository.entries['embed-1']?.localPath, '/models/embed-1.onnx');
    expect(registryRepository.entries['embed-1']?.checksum, 'sha256:verified-embed-1');
  });

  test('startDownload downloads all required multimodal artifacts before saving registry entry', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final downloadService = _FakeDownloadService();
    final runtimeBridge = _RecordingMultimodalLlmRuntimeBridge(
      ensureResult: <String, dynamic>{
        'status': 'runtime_unavailable',
        'ready': false,
        'message': '当前 native runtime 不支持 MiniCPM-V 4.6 多模态推理，请更新 runtime。',
      },
    );
    const modelUrl = 'https://example.com/MiniCPM-V-4_6-Q4_K_M.gguf';
    const mmprojUrl = 'https://example.com/mmproj-model-f16.gguf';
    downloadService.setResultForSource(
      sourceUrl: modelUrl,
      result: const ModelDownloadResult(
        localPath: '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf',
        totalBytes: 10,
        verifiedChecksum: 'sha256:model',
      ),
    );
    downloadService.setResultForSource(
      sourceUrl: mmprojUrl,
      result: const ModelDownloadResult(
        localPath: '/models/minicpm/mmproj-model-f16.gguf',
        totalBytes: 20,
        verifiedChecksum: 'sha256:mmproj',
      ),
    );
    const entry = ModelCatalogEntry(
      id: 'minicpm_v_4_6_q4_k_m',
      type: 'multimodal_llm',
      tier: 'local_multimodal',
      displayName: 'MiniCPM-V 4.6 Q4_K_M Multimodal',
      description: 'Requires LLM GGUF plus mmproj-model-f16.gguf.',
      sizeBytes: 30,
      minRamMb: 6144,
      recommendedTier: 'vision_language_local',
      sources: <ModelSourceEntry>[
        ModelSourceEntry(
          id: 'minicpm-v-4-6-q4-k-m-llm',
          label: 'HuggingFace MiniCPM-V 4.6 GGUF LLM',
          role: 'model',
          url: modelUrl,
          checksum: 'sha256:model',
        ),
        ModelSourceEntry(
          id: 'minicpm-v-4-6-mmproj-f16',
          label: 'HuggingFace MiniCPM-V 4.6 mmproj',
          role: 'mmproj',
          url: mmprojUrl,
          checksum: 'sha256:mmproj',
        ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        multimodalLlmRuntimeBridgeProvider.overrideWithValue(runtimeBridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
          entry: entry,
          source: entry.sources.first,
        );

    expect(downloadService.invocations.map((item) => item.sourceUrl), containsAll(<String>[modelUrl, mmprojUrl]));
    final saved = registryRepository.entries['minicpm_v_4_6_q4_k_m'];
    expect(saved, isNotNull);
    expect(saved!.localPath, '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf');
    expect(saved.artifactPathForRole('model'), '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf');
    expect(saved.artifactPathForRole('mmproj'), '/models/minicpm/mmproj-model-f16.gguf');
    expect(runtimeBridge.ensureCalls, 1);
    expect(runtimeBridge.lastModelPath, '/models/minicpm/MiniCPM-V-4_6-Q4_K_M.gguf');
    expect(runtimeBridge.lastMmprojPath, '/models/minicpm/mmproj-model-f16.gguf');
    expect(saved.enabled, isFalse);
    expect(saved.isInstalled, isFalse);
  });

  test('startDownload persists downloading status before first progress callback', () async {
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
    downloadService.progressGate = Completer<void>();

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    final startFuture = container.read(modelDownloadControllerProvider).startDownload(
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
                id: 'source-1',
                label: '镜像源',
                url: 'https://example.com/embed-1.onnx',
                checksum: 'sha256:verified-embed-1',
              ),
            ],
          ),
          source: const ModelSourceEntry(
            id: 'source-1',
            label: '镜像源',
            url: 'https://example.com/embed-1.onnx',
            checksum: 'sha256:verified-embed-1',
          ),
        );

    await Future<void>.delayed(Duration.zero);

    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-1')?.status,
      ModelDownloadStatus.downloading,
    );

    downloadService.progressGate!.complete();
    await startFuture;
  });

  test('startDownload resumes a paused task from existing partial bytes for the same source', () async {
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

    downloadRepository.tasksById['task-source-a'] = buildTask(
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

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
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

    expect(downloadService.inspectedKeys, contains('embed-1|https://example.com/embed-1.onnx'));
    expect(downloadService.lastResumeFromBytes, 1536);
    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status,
      ModelDownloadStatus.completed,
    );
  });

  test('modelDownloadTasksProvider normalizes stale downloading task to paused with local partial bytes when catalog source exists', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final downloadService = _FakeDownloadService();
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

    downloadRepository.tasksById['task-downloading'] = buildTask(
      id: 'task-downloading',
      modelId: 'embed-1',
      sourceId: 'source-a',
      status: ModelDownloadStatus.downloading,
      downloadedBytes: 32,
    );

    downloadService.setTarget(
      modelId: 'embed-1',
      sourceUrl: 'https://example.com/embed-1.onnx',
      existingBytes: 1536,
      localPath: '/partials/embed-1-source-a.partial',
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
      ],
    );

    addTearDown(container.dispose);

    final tasks = await container.read(modelDownloadTasksProvider.future);
    final normalized = tasks.singleWhere((task) => task.id == 'task-downloading');

    expect(normalized.status, ModelDownloadStatus.paused);
    expect(normalized.downloadedBytes, 1536);
    expect(downloadRepository.tasksById['task-downloading']?.status, ModelDownloadStatus.paused);
    expect(downloadRepository.tasksById['task-downloading']?.downloadedBytes, 1536);
  });

  test('modelRegistryEntriesProvider marks checksum-mismatched installed file as corrupted', () async {
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
      checksum: 'sha256:expected-embed-1',
      enabled: true,
      installedAt: null,
      filePresent: true,
    );
    downloadService.existingPaths.add('/models/embed-1.onnx');
    downloadService.checksumMismatchPaths.add('/models/embed-1.onnx');

    final container = ProviderContainer(
      overrides: [
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
      ],
    );

    addTearDown(container.dispose);

    final entries = await container.read(modelRegistryEntriesProvider.future);

    expect(entries.single.filePresent, isTrue);
    expect(entries.single.enabled, isFalse);
    expect(entries.single.integrityStatus, ModelIntegrityStatus.corrupted);
  });

  test('modelRegistryEntriesProvider adopts a complete local llm file from catalog when registry entry is missing', () async {
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
              checksum: 'sha256:verified-qwen',
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

    final container = ProviderContainer(
      overrides: [
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
      ],
    );

    addTearDown(container.dispose);

    final entries = await container.read(modelRegistryEntriesProvider.future);
    final adopted = entries.singleWhere((entry) => entry.id == 'qwen-local');

    expect(adopted.localPath, '/models/qwen-local.gguf');
    expect(adopted.checksum, 'sha256:verified-qwen');
    expect(adopted.sizeBytes, 8192);
    expect(adopted.filePresent, isTrue);
    expect(adopted.integrityStatus, ModelIntegrityStatus.valid);
    expect(adopted.enabled, isTrue);
    expect(registryRepository.entries['qwen-local']?.localPath, '/models/qwen-local.gguf');
  });

  test('modelRegistryEntriesProvider adopts a checksum-valid local llm file even when catalog size is stale', () async {
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
              checksum: 'sha256:verified-qwen',
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

    final container = ProviderContainer(
      overrides: [
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
      ],
    );

    addTearDown(container.dispose);

    final entries = await container.read(modelRegistryEntriesProvider.future);
    final adopted = entries.singleWhere((entry) => entry.id == 'qwen-local');

    expect(adopted.localPath, '/models/qwen-local.gguf');
    expect(adopted.checksum, 'sha256:verified-qwen');
    expect(adopted.sizeBytes, 8192);
    expect(adopted.filePresent, isTrue);
    expect(adopted.integrityStatus, ModelIntegrityStatus.valid);
    expect(adopted.enabled, isTrue);
  });

  test('startDownload re-downloads a disabled installed model instead of short-circuiting on file presence', () async {
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
      checksum: 'sha256:expected-embed-1',
      enabled: false,
      installedAt: null,
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.corrupted,
    );
    downloadService.existingPaths.add('/models/embed-1.onnx');

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
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
  });

  test('embeddingRuntimeStatesProvider reports corrupted when installed embedding file fails checksum revalidation', () async {
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
      checksum: 'sha256:expected-embed-1',
      enabled: true,
      installedAt: null,
      filePresent: true,
    );
    downloadService.existingPaths.add('/models/embed-1.onnx');
    downloadService.checksumMismatchPaths.add('/models/embed-1.onnx');

    final container = ProviderContainer(
      overrides: [
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    final states = await container.read(embeddingRuntimeStatesProvider.future);

    expect(states['embed-1']?.ready, isFalse);
    expect(states['embed-1']?.status, EmbeddingRuntimeStatus.corrupted);
    expect(states['embed-1']?.reason, contains('校验失败'));
    expect(bridge.inspectCalls, 0);
  });

  test('llmRuntimeStatesProvider reports corrupted when installed llm file fails checksum revalidation', () async {
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
      checksum: 'sha256:expected-llm-1',
      enabled: true,
      installedAt: null,
      filePresent: true,
    );
    downloadService.existingPaths.add('/models/phi.gguf');
    downloadService.checksumMismatchPaths.add('/models/phi.gguf');

    final container = ProviderContainer(
      overrides: [
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
  });

  test('startDownload validates llm runtime after download completes', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final llmBridge = _RecordingLlmRuntimeBridge();
    final downloadService = _FakeDownloadService(
      result: const ModelDownloadResult(
        localPath: '/models/phi.gguf',
        totalBytes: 8192,
        verifiedChecksum: 'sha256:verified-llm-1',
      ),
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
          entry: const ModelCatalogEntry(
            id: 'llm-1',
            type: 'llm',
            tier: 'local',
            displayName: 'Phi Local',
            description: '用于本地问答。',
            sizeBytes: 8192,
            minRamMb: 2048,
            recommendedTier: 'local',
            sources: <ModelSourceEntry>[
              ModelSourceEntry(
                id: 'source-1',
                label: '镜像源',
                url: 'https://example.com/phi.gguf',
                checksum: 'sha256:verified-llm-1',
              ),
            ],
          ),
           source: const ModelSourceEntry(
             id: 'source-1',
             label: '镜像源',
             url: 'https://example.com/phi.gguf',
             checksum: 'sha256:verified-llm-1',
           ),
         );

    expect(llmBridge.ensureCalls, 1);
    expect(llmBridge.lastModelId, 'llm-1');
    expect(llmBridge.lastModelPath, '/models/phi.gguf');
    expect(registryRepository.entries['llm-1']?.localPath, '/models/phi.gguf');
    expect(registryRepository.entries['llm-1']?.checksum, 'sha256:verified-llm-1');
  });

  test('startDownload keeps llm model disabled when runtime verification returns degraded', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final llmBridge = _RecordingLlmRuntimeBridge(
      ensureResult: <String, dynamic>{
        'ready': false,
        'status': 'degraded',
        'reason': '真实 probe failed',
        'modelPath': '/models/phi.gguf',
        'checkedAt': DateTime(2026, 4, 26).millisecondsSinceEpoch,
      },
    );
    final downloadService = _FakeDownloadService(
      result: const ModelDownloadResult(
        localPath: '/models/phi.gguf',
        totalBytes: 8192,
        verifiedChecksum: 'sha256:verified-llm-1',
      ),
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
          entry: const ModelCatalogEntry(
            id: 'llm-1',
            type: 'llm',
            tier: 'local',
            displayName: 'Phi Local',
            description: '用于本地问答。',
            sizeBytes: 8192,
            minRamMb: 2048,
            recommendedTier: 'local',
            sources: <ModelSourceEntry>[
              ModelSourceEntry(
                id: 'source-1',
                label: '镜像源',
                url: 'https://example.com/phi.gguf',
                checksum: 'sha256:verified-llm-1',
              ),
            ],
          ),
           source: const ModelSourceEntry(
             id: 'source-1',
             label: '镜像源',
             url: 'https://example.com/phi.gguf',
             checksum: 'sha256:verified-llm-1',
           ),
         );

    expect(llmBridge.ensureCalls, 1);
    expect(registryRepository.entries['llm-1']?.enabled, isFalse);
    expect(registryRepository.entries['llm-1']?.filePresent, isTrue);
    expect(registryRepository.entries['llm-1']?.checksum, 'sha256:verified-llm-1');
  });

  test('startDownload marks task failed and skips registry write on checksum mismatch', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final bridge = _RecordingEmbeddingRuntimeBridge();
    final downloadService = _FakeDownloadService(
      error: StateError('Checksum mismatch for embed-2'),
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
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
      downloadRepository.tasksByModelAndSource('embed-2', 'source-2')?.errorMessage,
      contains('Checksum mismatch'),
    );
    expect(registryRepository.entries.containsKey('embed-2'), isFalse);
  });

  test('startDownload keeps source-specific tasks separate for the same model', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final bridge = _RecordingEmbeddingRuntimeBridge();
    final downloadService = _FakeDownloadService(
      result: const ModelDownloadResult(
        localPath: '/models/embed-1.onnx',
        totalBytes: 4096,
        verifiedChecksum: 'sha256:verified-source-b',
      ),
    );

    downloadRepository.tasksById['task-source-a'] = buildTask(
      id: 'task-source-a',
      modelId: 'embed-1',
      sourceId: 'source-a',
      status: ModelDownloadStatus.paused,
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
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
                id: 'source-b',
                label: '备选镜像',
                url: 'https://example.com/embed-1-b.onnx',
                checksum: 'sha256:verified-source-b',
              ),
            ],
          ),
          source: const ModelSourceEntry(
            id: 'source-b',
            label: '备选镜像',
            url: 'https://example.com/embed-1-b.onnx',
            checksum: 'sha256:verified-source-b',
          ),
        );

    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status,
      ModelDownloadStatus.paused,
    );
    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-b')?.status,
      ModelDownloadStatus.completed,
    );
  });

  test('pause only affects the latest task for the selected source', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final downloadService = _FakeDownloadService(
      result: const ModelDownloadResult(
        localPath: '/models/embed-1.onnx',
        totalBytes: 4096,
        verifiedChecksum: 'sha256:verified-source-a',
      ),
    );

    downloadRepository.tasksById['task-source-a'] = buildTask(
      id: 'task-source-a',
      modelId: 'embed-1',
      sourceId: 'source-a',
      status: ModelDownloadStatus.downloading,
    );
    downloadRepository.tasksById['task-source-b'] = buildTask(
      id: 'task-source-b',
      modelId: 'embed-1',
      sourceId: 'source-b',
      status: ModelDownloadStatus.downloading,
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).pause('embed-1', sourceId: 'source-b');

    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status,
      ModelDownloadStatus.downloading,
    );
    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-b')?.status,
      ModelDownloadStatus.paused,
    );
  });

  test('startDownload adopts pre-existing complete local GGUF file matching size and checksum without re-downloading', () async {
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

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
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
                checksum: 'sha256:verified-qwen',
              ),
            ],
          ),
          source: const ModelSourceEntry(
            id: 'source-1',
            label: '镜像源',
            url: 'https://example.com/qwen.gguf',
            checksum: 'sha256:verified-qwen',
          ),
        );

    // No download should have been triggered
    expect(downloadService.invocations, isEmpty);
    // Registry should be written with the local path and valid checksum
    expect(registryRepository.entries['qwen-local'], isNotNull);
    expect(registryRepository.entries['qwen-local']?.localPath, '/models/qwen.gguf');
    expect(registryRepository.entries['qwen-local']?.checksum, 'sha256:verified-qwen');
    expect(registryRepository.entries['qwen-local']?.sizeBytes, 8192);
    expect(registryRepository.entries['qwen-local']?.integrityStatus, ModelIntegrityStatus.valid);
    expect(registryRepository.entries['qwen-local']?.enabled, isTrue);
    // Task should be marked completed
    expect(
      downloadRepository.tasksByModelAndSource('qwen-local', 'source-1')?.status,
      ModelDownloadStatus.completed,
    );
    // LLM runtime ensureModelReady should have been called for llm entry
    expect(llmBridge.ensureCalls, 1);
    expect(llmBridge.lastModelId, 'qwen-local');
    expect(llmBridge.lastModelPath, '/models/qwen.gguf');
  });

  test('startDownload retries fallback source when selected source fails with checksum mismatch', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final bridge = _RecordingEmbeddingRuntimeBridge();
    final downloadService = _FakeDownloadService();

    downloadService.setErrorForSource(
      sourceUrl: 'https://example.com/embed-1-a.onnx',
      error: StateError('Checksum mismatch for source-a'),
    );
    downloadService.setResultForSource(
      sourceUrl: 'https://example.com/embed-1-b.onnx',
      result: const ModelDownloadResult(
        localPath: '/models/embed-1.onnx',
        totalBytes: 4096,
        verifiedChecksum: 'sha256:verified-source-b',
      ),
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
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
                url: 'https://example.com/embed-1-a.onnx',
                checksum: 'sha256:verified-source-a',
              ),
              ModelSourceEntry(
                id: 'source-b',
                label: '备用镜像',
                url: 'https://example.com/embed-1-b.onnx',
                checksum: 'sha256:verified-source-b',
              ),
            ],
          ),
          source: const ModelSourceEntry(
            id: 'source-a',
            label: '主镜像',
            url: 'https://example.com/embed-1-a.onnx',
            checksum: 'sha256:verified-source-a',
          ),
        );

    expect(downloadService.invocations.length, 2);
    expect(downloadService.invocations[0].sourceUrl, 'https://example.com/embed-1-a.onnx');
    expect(downloadService.invocations[1].sourceUrl, 'https://example.com/embed-1-b.onnx');
    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-a')?.status,
      ModelDownloadStatus.failed,
    );
    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-b')?.status,
      ModelDownloadStatus.completed,
    );
    expect(registryRepository.entries['embed-1']?.checksum, 'sha256:verified-source-b');
  });

  test('startDownload resets resumeFromBytes to zero when switching to a different source', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final bridge = _RecordingEmbeddingRuntimeBridge();
    final downloadService = _FakeDownloadService();

    downloadService.setErrorForSource(
      sourceUrl: 'https://example.com/embed-1-a.onnx',
      error: StateError('Checksum mismatch for source-a'),
    );
    downloadService.setResultForSource(
      sourceUrl: 'https://example.com/embed-1-b.onnx',
      result: const ModelDownloadResult(
        localPath: '/models/embed-1.onnx',
        totalBytes: 4096,
        verifiedChecksum: 'sha256:verified-source-b',
      ),
    );
    downloadService.setTarget(
      modelId: 'embed-1',
      sourceUrl: 'https://example.com/embed-1-a.onnx',
      existingBytes: 1024,
      localPath: '/partials/embed-1.partial',
    );
    downloadService.setTarget(
      modelId: 'embed-1',
      sourceUrl: 'https://example.com/embed-1-b.onnx',
      existingBytes: 2048,
      localPath: '/partials/embed-1.partial',
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
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
                url: 'https://example.com/embed-1-a.onnx',
                checksum: 'sha256:verified-source-a',
              ),
              ModelSourceEntry(
                id: 'source-b',
                label: '备用镜像',
                url: 'https://example.com/embed-1-b.onnx',
                checksum: 'sha256:verified-source-b',
              ),
            ],
          ),
          source: const ModelSourceEntry(
            id: 'source-a',
            label: '主镜像',
            url: 'https://example.com/embed-1-a.onnx',
            checksum: 'sha256:verified-source-a',
          ),
        );

    expect(downloadService.invocations.length, 2);
    expect(downloadService.invocations[0].resumeFromBytes, 1024);
    expect(downloadService.invocations[1].resumeFromBytes, 0);
  });

  test('startDownload probes fallback sources and prefers healthier fallback ordering after selected source fails', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final bridge = _RecordingEmbeddingRuntimeBridge();
    final downloadService = _FakeDownloadService();
    final probeService = _FakeModelSourceProbeService();

    downloadService.setErrorForSource(
      sourceUrl: 'https://example.com/embed-1-a.onnx',
      error: StateError('Checksum mismatch for source-a'),
    );
    downloadService.setResultForSource(
      sourceUrl: 'https://example.com/embed-1-c.onnx',
      result: const ModelDownloadResult(
        localPath: '/models/embed-1.onnx',
        totalBytes: 4096,
        verifiedChecksum: 'sha256:verified-source-c',
      ),
    );

    probeService.setResult(
      const ModelSourceProbeResult(
        sourceId: 'source-b',
        reachable: true,
        statusCode: 200,
        contentLength: 4096,
        rangeSupported: false,
        latencyMs: 180,
        usedFallbackRangeProbe: false,
      ),
    );
    probeService.setResult(
      const ModelSourceProbeResult(
        sourceId: 'source-c',
        reachable: true,
        statusCode: 200,
        contentLength: 4096,
        rangeSupported: true,
        latencyMs: 40,
        usedFallbackRangeProbe: false,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        modelSourceProbeServiceProvider.overrideWithValue(probeService),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).startDownload(
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
                url: 'https://example.com/embed-1-a.onnx',
                checksum: 'sha256:verified-source-a',
              ),
              ModelSourceEntry(
                id: 'source-b',
                label: '次优镜像',
                url: 'https://example.com/embed-1-b.onnx',
                checksum: 'sha256:verified-source-b',
              ),
              ModelSourceEntry(
                id: 'source-c',
                label: '健康镜像',
                url: 'https://example.com/embed-1-c.onnx',
                checksum: 'sha256:verified-source-c',
              ),
            ],
          ),
          source: const ModelSourceEntry(
            id: 'source-a',
            label: '主镜像',
            url: 'https://example.com/embed-1-a.onnx',
            checksum: 'sha256:verified-source-a',
          ),
        );

    expect(downloadService.invocations.length, 2);
    expect(downloadService.invocations[0].sourceUrl, 'https://example.com/embed-1-a.onnx');
    expect(downloadService.invocations[1].sourceUrl, 'https://example.com/embed-1-c.onnx');
    expect(downloadRepository.tasksByModelAndSource('embed-1', 'source-b'), isNull);
    expect(
      downloadRepository.tasksByModelAndSource('embed-1', 'source-c')?.status,
      ModelDownloadStatus.completed,
    );
  });

  test('revalidateInstalledModel marks checksum-mismatched installed model as corrupted and disabled', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final downloadService = _FakeDownloadService();

    // Registry entry with corrupted file (checksum mismatch)
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
      checksum: 'sha256:expected-embed-1',
      enabled: true,
      installedAt: null,
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.unknown,
    );
    downloadService.existingPaths.add('/models/embed-1.onnx');
    downloadService.checksumMismatchPaths.add('/models/embed-1.onnx');

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).revalidateInstalledModel('embed-1');

    // Should persist the corrupted state
    expect(registryRepository.entries['embed-1']?.filePresent, isTrue);
    expect(registryRepository.entries['embed-1']?.enabled, isFalse);
    expect(registryRepository.entries['embed-1']?.integrityStatus, ModelIntegrityStatus.corrupted);
  });

  test('revalidateInstalledModel marks valid installed model as valid and enabled', () async {
    final downloadRepository = _MemoryDownloadRepository();
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
      checksum: 'sha256:expected-embed-1',
      enabled: true,
      installedAt: null,
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.unknown,
    );
    downloadService.existingPaths.add('/models/embed-1.onnx');
    // No checksumMismatchPaths entry → checksum passes

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).revalidateInstalledModel('embed-1');

    expect(registryRepository.entries['embed-1']?.filePresent, isTrue);
    expect(registryRepository.entries['embed-1']?.enabled, isTrue);
    expect(registryRepository.entries['embed-1']?.integrityStatus, ModelIntegrityStatus.valid);
  });

  test('revalidateInstalledModel re-enables a recovered installed model after checksum passes', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final downloadService = _FakeDownloadService();
    final llmBridge = _RecordingLlmRuntimeBridge();

    registryRepository.entries['llm-1'] = const ModelRegistryEntry(
      id: 'llm-1',
      type: 'llm',
      provider: 'builtin_catalog',
      name: 'Qwen Local',
      version: '1.0.0',
      sizeBytes: 4096,
      quantization: 'Q4_K_M',
      minRamMb: 2048,
      recommendedTier: 'local',
      localPath: '/models/qwen.gguf',
      checksum: 'sha256:expected-qwen',
      enabled: false,
      installedAt: null,
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.corrupted,
    );
    downloadService.existingPaths.add('/models/qwen.gguf');

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).revalidateInstalledModel('llm-1');

    expect(registryRepository.entries['llm-1']?.filePresent, isTrue);
    expect(registryRepository.entries['llm-1']?.enabled, isTrue);
    expect(registryRepository.entries['llm-1']?.integrityStatus, ModelIntegrityStatus.valid);
    expect(llmBridge.ensureCalls, 1);
  });

  test('revalidateInstalledModel runs llm readiness probe and exposes ready runtime state', () async {
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

    registryRepository.entries['llm-1'] = const ModelRegistryEntry(
      id: 'llm-1',
      type: 'llm',
      provider: 'builtin_catalog',
      name: 'Qwen Local',
      version: '1.0.0',
      sizeBytes: 4096,
      quantization: 'Q4_K_M',
      minRamMb: 2048,
      recommendedTier: 'local',
      localPath: '/models/qwen.gguf',
      checksum: 'sha256:expected-qwen',
      enabled: false,
      installedAt: null,
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.corrupted,
    );
    downloadService.existingPaths.add('/models/qwen.gguf');

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        llmRuntimeBridgeProvider.overrideWithValue(llmBridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).revalidateInstalledModel('llm-1');
    final runtimeStates = await container.read(llmRuntimeStatesProvider.future);

    expect(llmBridge.ensureCalls, greaterThanOrEqualTo(1));
    expect(llmBridge.lastModelId, 'llm-1');
    expect(llmBridge.lastModelPath, '/models/qwen.gguf');
    expect(runtimeStates['llm-1']?.ready, isTrue);
    expect(runtimeStates['llm-1']?.status, LlmRuntimeStatus.ready);
  });

  test('repairInstalledModel triggers fresh download for a broken installed model using catalog entry', () async {
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

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
        embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
      ],
    );

    addTearDown(container.dispose);

    await container.read(modelDownloadControllerProvider).repairInstalledModel('embed-1');

    // Should have triggered download via startDownload
    expect(downloadService.invocations, hasLength(1));
    expect(downloadService.invocations[0].modelId, 'embed-1');
    expect(downloadService.invocations[0].sourceUrl, 'https://example.com/embed-1.onnx');
    expect(downloadService.deletedPaths, contains('/models/embed-1.onnx'));
    // After repair, model should be re-registered as valid
    expect(registryRepository.entries['embed-1']?.checksum, 'sha256:verified-embed-1');
    expect(registryRepository.entries['embed-1']?.integrityStatus, ModelIntegrityStatus.valid);
  });

  test('repairInstalledModel safely handles missing catalog entry with no-op', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final downloadService = _FakeDownloadService();
    final catalogRepository = _MemoryCatalogRepository(const <ModelCatalogEntry>[]);

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

    final container = ProviderContainer(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        modelCatalogRepositoryProvider.overrideWithValue(catalogRepository),
      ],
    );

    addTearDown(container.dispose);

    // Should not throw even though model has no catalog entry
    await container.read(modelDownloadControllerProvider).repairInstalledModel('unknown-model');

    // No download should have been triggered
    expect(downloadService.invocations, isEmpty);
    // Registry entry remains unchanged (no crash)
    expect(registryRepository.entries['unknown-model']?.enabled, isFalse);
  });
}
