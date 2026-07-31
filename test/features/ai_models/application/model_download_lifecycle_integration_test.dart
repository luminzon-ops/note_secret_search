import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_runtime_providers.dart';
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
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';

import 'model_runtime_fixture.dart';

const _embeddingCatalogEntry = ModelCatalogEntry(
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
);

const _missingEmbeddingRegistryEntry = ModelRegistryEntry(
  id: 'model-1',
  type: 'embedding',
  provider: 'builtin_catalog',
  name: 'Model',
  version: '1.0.0',
  sizeBytes: 10,
  quantization: null,
  minRamMb: 512,
  recommendedTier: 'mvp',
  localPath: '/support/models/model-1/model.onnx',
  checksum: 'sha256:old-model',
  enabled: false,
  installedAt: null,
  filePresent: false,
  integrityStatus: ModelIntegrityStatus.unknown,
);

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
        repository: downloadRepository,
        registryRepository: registryRepository,
        downloadService: downloadService,
        lifecycleStore: lifecycleStore,
        artifactStore: const _NoopArtifactStore(),
        runtimeCoordinator: ref.read(modelRuntimeCoordinatorProvider),
        loadRegistryEntries: () =>
            ref.read(modelRegistryEntriesProvider.future),
        loadCatalogEntries: () => ref.read(modelCatalogEntriesProvider.future),
        invalidateDownloadTasks: () =>
            ref.invalidate(modelDownloadTasksProvider),
        invalidateRegistryEntries: () =>
            ref.invalidate(modelRegistryEntriesProvider),
        invalidateEmbeddingRuntimeStates: () =>
            ref.invalidate(embeddingRuntimeStatesProvider),
        logger: const AppLogger(),
      );
    });
    final container = ProviderContainer(
      overrides: <Override>[
        ...modelRuntimeFixtureOverrides(),
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

  test(
    'replacement releases cached embedding session when old file is missing',
    () async {
      final downloadRepository = _MemoryDownloadRepository();
      final registryRepository = _MemoryRegistryRepository()
        ..entry = _missingEmbeddingRegistryEntry;
      final lifecycleStore = _RecordingLifecycleStore(
        downloadRepository: downloadRepository,
        registryRepository: registryRepository,
      );
      final downloadService = _SuccessfulDownloadService();
      final writeFence = SearchIndexWriteFence();
      var releaseBeforeDownload = false;
      int? revisionObservedDuringRelease;
      final bridge = _RecordingEmbeddingRuntimeBridge(
        onRelease: (modelId) {
          releaseBeforeDownload = !downloadService.downloaded;
          revisionObservedDuringRelease = writeFence.revision;
        },
      );
      final controllerProvider = Provider<ModelDownloadController>((ref) {
        return ModelDownloadController(
          repository: downloadRepository,
          registryRepository: registryRepository,
          downloadService: downloadService,
          lifecycleStore: lifecycleStore,
          artifactStore: const _NoopArtifactStore(),
          runtimeCoordinator: ref.read(modelRuntimeCoordinatorProvider),
          loadRegistryEntries: () =>
              ref.read(modelRegistryEntriesProvider.future),
          loadCatalogEntries: () =>
              ref.read(modelCatalogEntriesProvider.future),
          invalidateDownloadTasks: () =>
              ref.invalidate(modelDownloadTasksProvider),
          invalidateRegistryEntries: () =>
              ref.invalidate(modelRegistryEntriesProvider),
          invalidateEmbeddingRuntimeStates: () =>
              ref.invalidate(embeddingRuntimeStatesProvider),
          logger: const AppLogger(),
        );
      });
      final container = ProviderContainer(
        overrides: <Override>[
          ...modelRuntimeFixtureOverrides(),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          modelCatalogEntriesProvider.overrideWith(
            (ref) async => const <ModelCatalogEntry>[_embeddingCatalogEntry],
          ),
          modelDownloadRepositoryProvider.overrideWithValue(downloadRepository),
          modelRegistryRepositoryProvider.overrideWithValue(registryRepository),
          modelLifecycleStoreProvider.overrideWithValue(lifecycleStore),
          modelDownloadServiceProvider.overrideWithValue(downloadService),
          searchIndexWriteFenceProvider.overrideWithValue(writeFence),
          embeddingRuntimeBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(controllerProvider)
          .startDownload(
            entry: _embeddingCatalogEntry,
            source: _embeddingCatalogEntry.sources.single,
          );

      expect(bridge.releasedModelIds, <String>['model-1']);
      expect(releaseBeforeDownload, isTrue);
      expect(revisionObservedDuringRelease, 1);
      expect(lifecycleStore.commitCalls, 1);
      expect(registryRepository.entry?.checksum, 'sha256:model');
    },
  );
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
