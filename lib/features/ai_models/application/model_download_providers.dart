import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/multimodal_llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/local_llm_engine.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_source_probe_service.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:uuid/uuid.dart';

final modelDownloadRepositoryProvider = Provider<ModelDownloadRepository>((ref) {
  return SqliteModelDownloadRepository(database: ref.watch(appDatabaseProvider));
});

final modelRegistryRepositoryProvider = Provider<ModelRegistryRepository>((ref) {
  return SqliteModelRegistryRepository(database: ref.watch(appDatabaseProvider));
});

final modelRegistryEntriesProvider = FutureProvider<List<ModelRegistryEntry>>((ref) async {
  final repository = ref.watch(modelRegistryRepositoryProvider);
  final downloadService = ref.watch(modelDownloadServiceProvider);
  final catalogEntries = await ref.watch(modelCatalogEntriesProvider.future);
  final existingEntries = await repository.listInstalledModels();
  final entriesById = <String, ModelRegistryEntry>{
    for (final entry in existingEntries) entry.id: entry,
  };

  for (final catalogEntry in catalogEntries) {
    if (entriesById.containsKey(catalogEntry.id)) {
      continue;
    }

    for (final source in catalogEntry.sources) {
      if (source.checksum.trim().isEmpty) {
        continue;
      }

      final target = await downloadService.inspectDownloadTarget(
        modelId: catalogEntry.id,
        sourceUrl: source.url,
      );
      if (!target.exists || target.existingBytes <= 0) {
        continue;
      }

      try {
        final verifiedChecksum = await downloadService.verifyChecksum(
          filePath: target.localPath,
          expectedChecksum: source.checksum,
        );
        final adopted = ModelRegistryEntry(
          id: catalogEntry.id,
          type: catalogEntry.type,
          provider: 'builtin_catalog',
          name: catalogEntry.displayName,
          version: null,
          sizeBytes: target.existingBytes,
          quantization: null,
          minRamMb: catalogEntry.minRamMb,
          recommendedTier: catalogEntry.recommendedTier,
          localPath: target.localPath,
          checksum: verifiedChecksum,
          enabled: true,
          installedAt: DateTime.now(),
          filePresent: true,
          integrityStatus: ModelIntegrityStatus.valid,
        );
        await repository.save(adopted);
        entriesById[adopted.id] = adopted;
        break;
      } catch (_) {
        continue;
      }
    }
  }

  final entries = entriesById.values.toList(growable: false);
  final resolved = <ModelRegistryEntry>[];

  for (final entry in entries) {
    final present = await downloadService.fileExists(entry.localPath);
    var normalized = entry.copyWith(
      filePresent: present,
      enabled: entry.enabled && present,
      integrityStatus: present ? entry.integrityStatus : ModelIntegrityStatus.unknown,
    );

    if (present && entry.localPath != null && entry.localPath!.trim().isNotEmpty) {
      final expectedChecksum = entry.checksum?.trim() ?? '';
      if (expectedChecksum.isNotEmpty) {
        try {
          await downloadService.verifyChecksum(
            filePath: entry.localPath!,
            expectedChecksum: expectedChecksum,
          );
          normalized = normalized.copyWith(integrityStatus: ModelIntegrityStatus.valid);
        } catch (_) {
          normalized = normalized.copyWith(
            enabled: false,
            integrityStatus: ModelIntegrityStatus.corrupted,
          );
        }
      }
    }

    if (normalized.enabled != entry.enabled || normalized.filePresent != entry.filePresent) {
      await repository.save(normalized);
    } else if (normalized.integrityStatus != entry.integrityStatus) {
      await repository.save(normalized);
    }
    resolved.add(normalized);
  }

  return resolved;
});

final embeddingRuntimeStatesProvider = FutureProvider<Map<String, EmbeddingEngineState>>((ref) async {
  final entries = await ref.watch(modelRegistryEntriesProvider.future);
  final embeddingEngine = ref.watch(embeddingEngineProvider);
  final resolved = <String, EmbeddingEngineState>{};

  for (final entry in entries) {
    if (entry.type != 'embedding') {
      continue;
    }

    if (entry.localPath == null || entry.localPath!.trim().isEmpty) {
      resolved[entry.id] = const EmbeddingEngineState(
        ready: false,
        reason: '尚未配置本地 embedding 模型文件。',
        status: EmbeddingRuntimeStatus.notInstalled,
      );
      continue;
    }

    if (!entry.filePresent) {
      resolved[entry.id] = EmbeddingEngineState(
        ready: false,
        reason: '本地模型文件缺失，需要重新下载或修复。',
        status: EmbeddingRuntimeStatus.missing,
        modelPath: entry.localPath,
      );
      continue;
    }

    if (entry.integrityStatus == ModelIntegrityStatus.corrupted) {
      resolved[entry.id] = EmbeddingEngineState(
        ready: false,
        reason: '本地模型文件校验失败，需要重新下载或修复。',
        status: EmbeddingRuntimeStatus.corrupted,
        modelPath: entry.localPath,
      );
      continue;
    }

    resolved[entry.id] = await embeddingEngine.getState(entry);
  }

  return resolved;
});

final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  return ModelDownloadService(
    dio: Dio(),
    logger: ref.watch(loggerProvider),
  );
});

final modelSourceProbeServiceProvider = Provider<ModelSourceProbeService>((ref) {
  return ModelSourceProbeService(
    dio: Dio(),
    logger: ref.watch(loggerProvider),
  );
});

final modelDownloadTasksProvider = FutureProvider<List<ModelDownloadTask>>((ref) async {
  final repository = ref.watch(modelDownloadRepositoryProvider);
  final downloadService = ref.watch(modelDownloadServiceProvider);
  final catalogEntries = await ref.watch(modelCatalogEntriesProvider.future);
  final catalogByModelId = <String, ModelCatalogEntry>{
    for (final entry in catalogEntries) entry.id: entry,
  };
  final tasks = await repository.listTasks();
  final resolved = <ModelDownloadTask>[];

  for (final task in tasks) {
    final catalogEntry = catalogByModelId[task.modelId];
    final source = catalogEntry?.sources.where((item) => item.id == task.sourceId).firstOrNull;
    if (catalogEntry == null || source == null) {
      resolved.add(task);
      continue;
    }

    final target = await downloadService.inspectDownloadTarget(
      modelId: task.modelId,
      sourceUrl: source.url,
    );

    var next = task;
    if (task.downloadedBytes != target.existingBytes) {
      next = next.copyWith(
        downloadedBytes: target.existingBytes,
      );
    }

    if ((task.status == ModelDownloadStatus.queued || task.status == ModelDownloadStatus.downloading) &&
        target.existingBytes > 0) {
      next = next.copyWith(
        status: ModelDownloadStatus.paused,
        downloadedBytes: target.existingBytes,
        updatedAt: DateTime.now(),
      );
    }

    if (next != task) {
      await repository.saveTask(next);
    }
    resolved.add(next);
  }

  return resolved;
});

final modelDownloadControllerProvider = Provider<ModelDownloadController>((ref) {
  return ModelDownloadController(
    ref: ref,
    repository: ref.watch(modelDownloadRepositoryProvider),
    registryRepository: ref.watch(modelRegistryRepositoryProvider),
    downloadService: ref.watch(modelDownloadServiceProvider),
    logger: ref.watch(loggerProvider),
  );
});

class ModelDownloadController {
  ModelDownloadController({
    required Ref ref,
    required ModelDownloadRepository repository,
    required ModelRegistryRepository registryRepository,
    required ModelDownloadService downloadService,
    required AppLogger logger,
  })
      : _ref = ref,
        _repository = repository,
        _registryRepository = registryRepository,
        _downloadService = downloadService,
        _logger = logger;

  final Ref _ref;
  final ModelDownloadRepository _repository;
  final ModelRegistryRepository _registryRepository;
  final ModelDownloadService _downloadService;
  final AppLogger _logger;
  static const _uuid = Uuid();

  Future<void> enqueueDownload({
    required String modelId,
    required String sourceId,
    required int? totalBytes,
  }) async {
    final existing = await _repository.findLatestTaskByModelAndSource(modelId, sourceId);
    final now = DateTime.now();

    if (existing != null &&
        (existing.status == ModelDownloadStatus.queued ||
            existing.status == ModelDownloadStatus.downloading ||
            existing.status == ModelDownloadStatus.paused)) {
      final next = existing.copyWith(
        status: ModelDownloadStatus.queued,
        totalBytes: totalBytes ?? existing.totalBytes,
        errorMessage: null,
        clearErrorMessage: true,
        updatedAt: now,
      );
      await _repository.saveTask(next);
      _ref.invalidate(modelDownloadTasksProvider);
      return;
    }

    final task = ModelDownloadTask(
      id: _uuid.v4(),
      modelId: modelId,
      sourceId: sourceId,
      status: ModelDownloadStatus.queued,
      totalBytes: totalBytes,
      downloadedBytes: 0,
      averageSpeed: null,
      errorMessage: null,
      resumable: true,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.saveTask(task);
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> markDownloading(String modelId) async {
    final task = await _repository.findLatestTaskByModel(modelId);
    if (task == null) {
      return;
    }

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.downloading,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> startDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
  }) async {
    if (!_isDownloadRuntimeSupported(entry)) {
      await enqueueDownload(
        modelId: entry.id,
        sourceId: source.id,
        totalBytes: entry.sizeBytes,
      );
      await markFailedForSource(
        entry.id,
        sourceId: source.id,
        message: '当前版本尚不支持 ${entry.type} 模型下载部署；需要专用 runtime 后才能安装。',
      );
      return;
    }

    if (entry.type == 'multimodal_llm') {
      await _startMultimodalDownload(entry: entry);
      return;
    }

    ModelRegistryEntry? existingRegistry = await _registryRepository.getById(entry.id);
    if (existingRegistry != null) {
      final normalizedEntries = await _ref.read(modelRegistryEntriesProvider.future);
      existingRegistry = normalizedEntries.where((item) => item.id == entry.id).firstOrNull ?? existingRegistry;

      final filePresent = await _downloadService.fileExists(existingRegistry.localPath);
      if (existingRegistry.isInstalled && filePresent) {
        _ref.invalidate(modelRegistryEntriesProvider);
        return;
      }
      if (filePresent) {
        await _downloadService.deleteLocalFile(existingRegistry.localPath);
      }
    }

    final candidates = await _orderedCandidateSources(entry: entry, selectedSource: source);

    // Check if the target file already exists with complete size and valid checksum.
    // If so, adopt it instead of re-downloading.
    final targetForAdoption = await _downloadService.inspectDownloadTarget(
      modelId: entry.id,
      sourceUrl: source.url,
    );
    if (targetForAdoption.exists &&
        targetForAdoption.existingBytes == entry.sizeBytes &&
        source.checksum.isNotEmpty) {
      try {
        final verifiedChecksum = await _downloadService.verifyChecksum(
          filePath: targetForAdoption.localPath,
          expectedChecksum: source.checksum,
        );
        // File is complete and valid — create a synthetic task and adopt it.
        final existingTask = await _repository.findLatestTaskByModelAndSource(entry.id, source.id);
        final taskForAdoption = existingTask ??
            ModelDownloadTask(
              id: _uuid.v4(),
              modelId: entry.id,
              sourceId: source.id,
              status: ModelDownloadStatus.queued,
              totalBytes: entry.sizeBytes,
              downloadedBytes: 0,
              averageSpeed: null,
              errorMessage: null,
              resumable: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
        await _completeSuccessfulDownload(
          entry: entry,
          source: source,
          task: taskForAdoption,
          result: ModelDownloadResult(
            localPath: targetForAdoption.localPath,
            totalBytes: targetForAdoption.existingBytes,
            verifiedChecksum: verifiedChecksum,
            resumed: false,
            fellBackToRestart: false,
            resumable: true,
          ),
        );
        return;
      } catch (_) {
        // Checksum failed — fall through to normal download behavior.
      }
    }

    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final allowResume = candidate.id == source.id;

      await enqueueDownload(
        modelId: entry.id,
        sourceId: candidate.id,
        totalBytes: entry.sizeBytes,
      );

      final target = await _downloadService.inspectDownloadTarget(
        modelId: entry.id,
        sourceUrl: candidate.url,
      );
      final resumeFromBytes = allowResume ? target.existingBytes : 0;

      final task = await _repository.findLatestTaskByModelAndSource(entry.id, candidate.id);
      if (task == null) {
        continue;
      }

      await _repository.saveTask(
        task.copyWith(
          status: ModelDownloadStatus.downloading,
          downloadedBytes: resumeFromBytes,
          totalBytes: entry.sizeBytes,
          errorMessage: null,
          clearErrorMessage: true,
          updatedAt: DateTime.now(),
        ),
      );
      _ref.invalidate(modelDownloadTasksProvider);

      try {
        final result = await _downloadService.download(
          taskId: task.id,
          modelId: entry.id,
          sourceUrl: candidate.url,
          expectedChecksum: candidate.checksum,
          resumeFromBytes: resumeFromBytes,
          onProgress: (progress) async {
            final current = await _repository.findLatestTaskByModelAndSource(entry.id, candidate.id);
            if (current == null) {
              return;
            }

            await _repository.saveTask(
              current.copyWith(
                status: ModelDownloadStatus.downloading,
                totalBytes: progress.totalBytes ?? current.totalBytes,
                downloadedBytes: progress.receivedBytes,
                averageSpeed: progress.averageSpeedBytesPerSecond,
                errorMessage: null,
                clearErrorMessage: true,
                updatedAt: DateTime.now(),
              ),
            );
            _ref.invalidate(modelDownloadTasksProvider);
          },
        );

        await _completeSuccessfulDownload(
          entry: entry,
          source: candidate,
          task: task,
          result: result,
        );
        return;
      } catch (error, stackTrace) {
        _logger.error('Model download failed for ${entry.id} via ${candidate.id}', error, stackTrace);
        final hasFallback = index < candidates.length - 1;
        final eligibleForFailover = hasFallback && _isFailoverEligible(error);
        final message = eligibleForFailover
            ? '当前来源失败，正在尝试其他下载源：$error'
            : (candidates.length > 1 ? '所有可用下载源均失败：$error' : error.toString());
        await markFailedForSource(entry.id, sourceId: candidate.id, message: message);
        if (!eligibleForFailover) {
          return;
        }
      }
    }
  }

  Future<List<ModelSourceEntry>> _orderedCandidateSources({
    required ModelCatalogEntry entry,
    required ModelSourceEntry selectedSource,
  }) async {
    final ordered = <ModelSourceEntry>[selectedSource];
    final fallbackSources = <ModelSourceEntry>[];
    for (final source in entry.sources) {
      if (source.id == selectedSource.id) {
        continue;
      }
      fallbackSources.add(source);
    }

    if (fallbackSources.isEmpty) {
      return ordered;
    }

    final probeService = _ref.read(modelSourceProbeServiceProvider);
    final probeResults = await Future.wait(
      fallbackSources.map(
        (candidate) => probeService.probeSource(
          source: candidate,
          expectedSizeBytes: entry.sizeBytes,
        ),
      ),
    );
    final rankedIds = rankProbeResults(
      probeResults,
      expectedSizeBytes: entry.sizeBytes,
    ).map((item) => item.sourceId).toList(growable: false);
    for (final sourceId in rankedIds) {
      final matched = fallbackSources.where((source) => source.id == sourceId).firstOrNull;
      if (matched != null) {
        ordered.add(matched);
      }
    }
    return ordered;
  }

  bool _isFailoverEligible(Object error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.response?.statusCode == 429 ||
          ((error.response?.statusCode ?? 0) >= 500);
    }

    final message = error.toString().toLowerCase();
    return message.contains('checksum mismatch') ||
        message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('socket') ||
        message.contains('dns') ||
        message.contains('429') ||
        message.contains('503') ||
        message.contains('502') ||
        message.contains('500');
  }

  bool _isDownloadRuntimeSupported(ModelCatalogEntry entry) {
    return entry.type == 'embedding' || entry.type == 'llm' || entry.type == 'multimodal_llm';
  }

  Future<void> _startMultimodalDownload({
    required ModelCatalogEntry entry,
  }) async {
    final requiredSources = entry.sources.where((source) => source.required).toList(growable: false);
    final results = <ModelSourceEntry, ModelDownloadResult>{};

    for (final source in requiredSources) {
      await enqueueDownload(
        modelId: entry.id,
        sourceId: source.id,
        totalBytes: null,
      );

      final task = await _repository.findLatestTaskByModelAndSource(entry.id, source.id);
      if (task == null) {
        continue;
      }

      await _repository.saveTask(
        task.copyWith(
          status: ModelDownloadStatus.downloading,
          downloadedBytes: 0,
          errorMessage: null,
          clearErrorMessage: true,
          updatedAt: DateTime.now(),
        ),
      );
      _ref.invalidate(modelDownloadTasksProvider);

      try {
        final result = await _downloadService.download(
          taskId: task.id,
          modelId: entry.id,
          sourceUrl: source.url,
          expectedChecksum: source.checksum,
          onProgress: (progress) async {
            final current = await _repository.findLatestTaskByModelAndSource(entry.id, source.id);
            if (current == null) {
              return;
            }
            await _repository.saveTask(
              current.copyWith(
                status: ModelDownloadStatus.downloading,
                totalBytes: progress.totalBytes ?? current.totalBytes,
                downloadedBytes: progress.receivedBytes,
                averageSpeed: progress.averageSpeedBytesPerSecond,
                errorMessage: null,
                clearErrorMessage: true,
                updatedAt: DateTime.now(),
              ),
            );
            _ref.invalidate(modelDownloadTasksProvider);
          },
        );
        results[source] = result;
        final current = await _repository.findLatestTaskByModelAndSource(entry.id, source.id) ?? task;
        await _repository.saveTask(
          current.copyWith(
            status: ModelDownloadStatus.completed,
            downloadedBytes: result.totalBytes,
            totalBytes: result.totalBytes,
            errorMessage: null,
            clearErrorMessage: true,
            updatedAt: DateTime.now(),
          ),
        );
      } catch (error, stackTrace) {
        _logger.error('Multimodal model artifact download failed for ${entry.id} via ${source.id}', error, stackTrace);
        await markFailedForSource(entry.id, sourceId: source.id, message: error.toString());
        return;
      }
    }

    await _completeSuccessfulMultimodalDownload(entry: entry, results: results);
  }

  Future<void> _completeSuccessfulMultimodalDownload({
    required ModelCatalogEntry entry,
    required Map<ModelSourceEntry, ModelDownloadResult> results,
  }) async {
    final artifacts = <ModelArtifactPath>[];
    for (final MapEntry<ModelSourceEntry, ModelDownloadResult> item in results.entries) {
      artifacts.add(
        ModelArtifactPath(
          role: item.key.role,
          sourceId: item.key.id,
          localPath: item.value.localPath,
          checksum: item.value.verifiedChecksum,
          sizeBytes: item.value.totalBytes,
        ),
      );
    }

    String? pathForRole(String role) {
      for (final artifact in artifacts) {
        if (artifact.role == role && artifact.localPath.isNotEmpty) {
          return artifact.localPath;
        }
      }
      return null;
    }

    final modelPath = pathForRole('model');
    final mmprojPath = pathForRole('mmproj');
    if (modelPath == null || mmprojPath == null) {
      await markFailed(entry.id, 'MiniCPM-V 必需模型文件不完整，请重新下载。');
      return;
    }

    final totalBytes = artifacts.fold<int>(0, (sum, artifact) => sum + (artifact.sizeBytes ?? 0));
    await _registryRepository.save(
      ModelRegistryEntry(
        id: entry.id,
        type: entry.type,
        provider: 'builtin_catalog',
        name: entry.displayName,
        version: null,
        sizeBytes: totalBytes == 0 ? null : totalBytes,
        quantization: null,
        minRamMb: entry.minRamMb,
        recommendedTier: entry.recommendedTier,
        localPath: modelPath,
        checksum: artifacts.map((artifact) => '${artifact.role}:${artifact.checksum ?? ''}').join('|'),
        enabled: true,
        installedAt: DateTime.now(),
        filePresent: true,
        integrityStatus: ModelIntegrityStatus.valid,
        artifacts: artifacts,
      ),
    );

    final runtimeResult = await _ref.read(multimodalLlmRuntimeBridgeProvider).ensureModelReady(
          modelId: entry.id,
          modelPath: modelPath,
          mmprojPath: mmprojPath,
        );
    final ready = runtimeResult['ready'] == true || runtimeResult['status'] == 'ready';
    final persisted = await _registryRepository.getById(entry.id);
    if (persisted != null) {
      await _registryRepository.save(
        persisted.copyWith(
          enabled: ready,
          filePresent: true,
        ),
      );
    }

    _ref.invalidate(modelDownloadTasksProvider);
    _ref.invalidate(modelRegistryEntriesProvider);
  }

  Future<void> _completeSuccessfulDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
    required ModelDownloadTask task,
    required ModelDownloadResult result,
  }) async {
    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.completed,
        downloadedBytes: result.totalBytes,
        totalBytes: result.totalBytes,
        updatedAt: DateTime.now(),
        errorMessage: null,
        clearErrorMessage: true,
      ),
    );

    await _registryRepository.save(
      ModelRegistryEntry(
        id: entry.id,
        type: entry.type,
        provider: 'builtin_catalog',
        name: entry.displayName,
        version: null,
        sizeBytes: result.totalBytes,
        quantization: null,
        minRamMb: entry.minRamMb,
        recommendedTier: entry.recommendedTier,
        localPath: result.localPath,
        checksum: result.verifiedChecksum,
        enabled: true,
        installedAt: DateTime.now(),
        filePresent: true,
        integrityStatus: ModelIntegrityStatus.valid,
      ),
    );

    if (entry.type == 'embedding') {
      final runtimeResult = await _ref.read(embeddingRuntimeBridgeProvider).ensureModelReady(
            modelId: entry.id,
            modelPath: result.localPath,
            tokenizer: entry.tokenizer,
            runtime: entry.runtime,
          );
      final runtimeState = mapEmbeddingEngineState(runtimeResult, fallbackPath: result.localPath);
      final persisted = await _registryRepository.getById(entry.id);
      if (persisted != null) {
        await _registryRepository.save(
          persisted.copyWith(
            enabled: runtimeState.status == EmbeddingRuntimeStatus.ready ||
                runtimeState.status == EmbeddingRuntimeStatus.installedUnverified,
            filePresent: runtimeState.status != EmbeddingRuntimeStatus.missing,
          ),
        );
      }
    }

    if (entry.type == 'llm') {
      final runtimeResult = await _ref.read(llmRuntimeBridgeProvider).ensureModelReady(
            modelId: entry.id,
            modelPath: result.localPath,
          );
      final runtimeState = mapLlmRuntimeState(runtimeResult, fallbackPath: result.localPath);
      final persisted = await _registryRepository.getById(entry.id);
      if (persisted != null) {
        await _registryRepository.save(
          persisted.copyWith(
            enabled: runtimeState.status == LlmRuntimeStatus.ready ||
                runtimeState.status == LlmRuntimeStatus.installedUnverified,
            filePresent: runtimeState.status != LlmRuntimeStatus.missing,
          ),
        );
      }
    }

    _ref.invalidate(modelDownloadTasksProvider);
    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(embeddingRuntimeStatesProvider);
    _ref.invalidate(llmRuntimeStatesProvider);
  }

  Future<void> pause(String modelId, {required String sourceId}) async {
    final task = await _repository.findLatestTaskByModelAndSource(modelId, sourceId);
    if (task == null) {
      return;
    }

    _downloadService.cancel(task.id);

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.paused,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> deleteInstalledModel(String modelId) async {
    final existing = await _registryRepository.getById(modelId);
    if (existing == null) {
      return;
    }

    await _downloadService.deleteLocalFile(existing.localPath);
    await _registryRepository.deleteById(modelId);
    await markFailed(modelId, '本地模型文件已删除，可重新下载。');
    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<bool> isInstalled(String modelId) async {
    final existing = await _registryRepository.getById(modelId);
    if (existing == null) {
      return false;
    }
    return _downloadService.fileExists(existing.localPath);
  }

  Future<void> markFailed(String modelId, String message) async {
    final task = await _repository.findLatestTaskByModel(modelId);
    if (task == null) {
      return;
    }

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.failed,
        errorMessage: message,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> markFailedForSource(String modelId, {required String sourceId, required String message}) async {
    final task = await _repository.findLatestTaskByModelAndSource(modelId, sourceId);
    if (task == null) {
      return;
    }

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.failed,
        errorMessage: message,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> markCompleted(String modelId) async {
    final task = await _repository.findLatestTaskByModel(modelId);
    if (task == null) {
      return;
    }

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.completed,
        downloadedBytes: task.totalBytes ?? task.downloadedBytes,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }

  /// Re-validates a single installed model: checks file presence and checksum,
  /// persists the resulting [filePresent], [enabled], and [integrityStatus],
  /// then invalidates the relevant providers.
  Future<void> revalidateInstalledModel(String modelId) async {
    _logger.info('revalidateInstalledModel:start modelId=$modelId');
    final entry = await _registryRepository.getById(modelId);
    if (entry == null) {
      _logger.warning('revalidateInstalledModel:missing-entry modelId=$modelId');
      return;
    }

    var normalized = await _normalizeRegistryEntry(entry);
    _logger.info(
      'revalidateInstalledModel:normalized modelId=$modelId '
      'type=${normalized.type} filePresent=${normalized.filePresent} '
      'enabled=${normalized.enabled} integrity=${normalized.integrityStatus.name}',
    );
    if (normalized.filePresent && normalized.integrityStatus == ModelIntegrityStatus.valid) {
      if (normalized.type == 'llm' && normalized.localPath != null && normalized.localPath!.trim().isNotEmpty) {
        _logger.info(
          'revalidateInstalledModel:ensureModelReady modelId=$modelId path=${normalized.localPath}',
        );
        final runtimeResult = await _ref.read(llmRuntimeBridgeProvider).ensureModelReady(
              modelId: normalized.id,
              modelPath: normalized.localPath!,
            );
        final runtimeState = mapLlmRuntimeState(runtimeResult, fallbackPath: normalized.localPath);
        _logger.info(
          'revalidateInstalledModel:ensureModelReady-result '
          'modelId=$modelId status=${runtimeState.status.name} ready=${runtimeState.ready} '
          'reason=${runtimeState.reason}',
        );
        normalized = normalized.copyWith(
          enabled: runtimeState.status == LlmRuntimeStatus.ready ||
              runtimeState.status == LlmRuntimeStatus.installedUnverified,
          filePresent: runtimeState.status != LlmRuntimeStatus.missing,
        );
      } else {
        normalized = normalized.copyWith(enabled: true);
      }
    }

    if (normalized.enabled != entry.enabled ||
        normalized.filePresent != entry.filePresent ||
        normalized.integrityStatus != entry.integrityStatus) {
      await _registryRepository.save(normalized);
      _logger.info(
        'revalidateInstalledModel:saved modelId=$modelId '
        'filePresent=${normalized.filePresent} enabled=${normalized.enabled} '
        'integrity=${normalized.integrityStatus.name}',
      );
    }

    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(embeddingRuntimeStatesProvider);
    _ref.invalidate(llmRuntimeStatesProvider);
    _logger.info('revalidateInstalledModel:invalidated modelId=$modelId');
  }

  /// Repairs a broken installed model by re-downloading it from the catalog.
  /// Uses the built-in catalog entry for the model and the first available source.
  /// If no matching catalog entry or no sources exist, this is a no-op.
  Future<void> repairInstalledModel(String modelId) async {
    final catalogEntries = await _ref.read(modelCatalogEntriesProvider.future);
    final catalogEntry = catalogEntries.where((e) => e.id == modelId).firstOrNull;

    if (catalogEntry == null || catalogEntry.sources.isEmpty) {
      return;
    }

    final firstSource = catalogEntry.sources.first;
    await startDownload(entry: catalogEntry, source: firstSource);
  }

  /// Normalizes a [ModelRegistryEntry] by checking file presence and checksum,
  /// returning an updated entry with corrected [filePresent], [enabled], and
  /// [integrityStatus]. Does NOT persist — caller decides when to save.
  Future<ModelRegistryEntry> _normalizeRegistryEntry(ModelRegistryEntry entry) async {
    final present = await _downloadService.fileExists(entry.localPath);

    var normalized = entry.copyWith(
      filePresent: present,
      enabled: entry.enabled && present,
      integrityStatus: present ? entry.integrityStatus : ModelIntegrityStatus.unknown,
    );

    if (present && entry.localPath != null && entry.localPath!.trim().isNotEmpty) {
      final expectedChecksum = entry.checksum?.trim() ?? '';
      if (expectedChecksum.isNotEmpty) {
        try {
          await _downloadService.verifyChecksum(
            filePath: entry.localPath!,
            expectedChecksum: expectedChecksum,
          );
          normalized = normalized.copyWith(
            enabled: true,
            integrityStatus: ModelIntegrityStatus.valid,
          );
        } catch (_) {
          normalized = normalized.copyWith(
            enabled: false,
            integrityStatus: ModelIntegrityStatus.corrupted,
          );
        }
      }
    }

    return normalized;
  }
}
