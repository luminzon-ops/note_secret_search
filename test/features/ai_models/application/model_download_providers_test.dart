import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';

class _MemoryDownloadRepository implements ModelDownloadRepository {
  final Map<String, ModelDownloadTask> tasks = <String, ModelDownloadTask>{};

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async => tasks[modelId];

  @override
  Future<List<ModelDownloadTask>> listTasks() async => tasks.values.toList(growable: false);

  @override
  Future<void> saveTask(ModelDownloadTask task) async {
    tasks[task.modelId] = task;
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

class _FakeDownloadService extends ModelDownloadService {
  _FakeDownloadService({required this.result}) : super(dio: Dio(), logger: const AppLogger());

  final ModelDownloadResult result;

  @override
  Future<ModelDownloadResult> download({
    required String taskId,
    required String modelId,
    required String sourceUrl,
    required void Function(ModelDownloadProgress progress) onProgress,
  }) async {
    onProgress(
      ModelDownloadProgress(
        receivedBytes: result.totalBytes,
        totalBytes: result.totalBytes,
        averageSpeedBytesPerSecond: 1024,
      ),
    );
    return result;
  }

  @override
  Future<bool> fileExists(String? path) async => path == result.localPath;
}

class _RecordingEmbeddingRuntimeBridge implements EmbeddingRuntimeBridge {
  int ensureCalls = 0;
  String? lastModelId;
  String? lastModelPath;

  @override
  Future<Map<String, dynamic>> embedText({required String modelId, required String modelPath, required String text}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({required String modelId, required String modelPath}) async {
    ensureCalls++;
    lastModelId = modelId;
    lastModelPath = modelPath;
    return <String, dynamic>{
      'status': 'ready',
      'reason': 'validated',
      'modelPath': modelPath,
      'checkedAt': DateTime(2026, 4, 26).millisecondsSinceEpoch,
      'vectorDimension': 384,
    };
  }

  @override
  Future<Map<String, dynamic>> inspectModel({required String modelId, required String modelPath}) async {
    return <String, dynamic>{
      'status': 'installedUnverified',
      'reason': 'pending',
      'modelPath': modelPath,
    };
  }

  @override
  Future<void> releaseModel({required String modelId}) async {}
}

void main() {
  test('startDownload validates embedding runtime after download completes', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final bridge = _RecordingEmbeddingRuntimeBridge();
    final downloadService = _FakeDownloadService(
      result: const ModelDownloadResult(localPath: '/models/embed-1.onnx', totalBytes: 4096),
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
              ModelSourceEntry(id: 'source-1', label: '镜像源', url: 'https://example.com/embed-1.onnx'),
            ],
          ),
          source: const ModelSourceEntry(
            id: 'source-1',
            label: '镜像源',
            url: 'https://example.com/embed-1.onnx',
          ),
        );

    expect(bridge.ensureCalls, 1);
    expect(bridge.lastModelId, 'embed-1');
    expect(bridge.lastModelPath, '/models/embed-1.onnx');
    expect(registryRepository.entries['embed-1']?.localPath, '/models/embed-1.onnx');
  });
}
