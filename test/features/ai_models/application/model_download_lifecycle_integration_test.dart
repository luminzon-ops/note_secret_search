import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime failure does not commit a partial installation', () async {
    final downloadRepository = _MemoryDownloadRepository();
    final registryRepository = _MemoryRegistryRepository();
    final lifecycleStore = _RecordingLifecycleStore(
      downloadRepository: downloadRepository,
      registryRepository: registryRepository,
    );
    final downloadService = _SuccessfulDownloadService();
    final controllerProvider = Provider<ModelDownloadController>((ref) {
      return ModelDownloadController(
        ref: ref,
        repository: downloadRepository,
        registryRepository: registryRepository,
        downloadService: downloadService,
        lifecycleStore: lifecycleStore,
        artifactStore: const _NoopArtifactStore(),
        logger: const AppLogger(),
      );
    });
    final container = ProviderContainer(
      overrides: <Override>[
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        modelCatalogEntriesProvider.overrideWith(
          (ref) async => const <ModelCatalogEntry>[
            ModelCatalogEntry(
              id: 'model-1',
              type: 'embedding',
              tier: 'mvp',
              displayName: 'Model',
              description: 'Test model',
              sizeBytes: 10,
              minRamMb: 512,
              recommendedTier: 'mvp',
              sources: <ModelSourceEntry>[
                ModelSourceEntry(
                  id: 'source-1',
                  label: 'Source',
                  url: 'https://example.com/model.onnx',
                  checksum: 'sha256:model',
                ),
                ModelSourceEntry(
                  id: 'source-2',
                  label: 'Fallback source',
                  url: 'https://mirror.example.com/model.onnx',
                  checksum: 'sha256:model',
                ),
              ],
            ),
          ],
        ),
        modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
        modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
        modelLifecycleStoreProvider.overrideWithValue(lifecycleStore),
        modelDownloadServiceProvider.overrideWithValue(downloadService),
        embeddingRuntimeBridgeProvider.overrideWithValue(
          const _ThrowingEmbeddingRuntimeBridge(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(controllerProvider)
        .startDownload(
          entry: const ModelCatalogEntry(
            id: 'model-1',
            type: 'embedding',
            tier: 'mvp',
            displayName: 'Model',
            description: 'Test model',
            sizeBytes: 10,
            minRamMb: 512,
            recommendedTier: 'mvp',
            sources: <ModelSourceEntry>[
              ModelSourceEntry(
                id: 'source-1',
                label: 'Source',
                url: 'https://example.com/model.onnx',
                checksum: 'sha256:model',
              ),
            ],
          ),
          source: const ModelSourceEntry(
            id: 'source-1',
            label: 'Source',
            url: 'https://example.com/model.onnx',
            checksum: 'sha256:model',
          ),
        );

    expect(lifecycleStore.commitCalls, 0);
    expect(downloadRepository.latest?.status, ModelDownloadStatus.failed);
    expect(registryRepository.entry, isNull);

    final refreshed = await container.read(modelRegistryEntriesProvider.future);
    expect(refreshed, isEmpty);
    expect(lifecycleStore.commitCalls, 0);
    expect(registryRepository.entry, isNull);
  });
}

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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> releaseModel({required String modelId}) async {}
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
