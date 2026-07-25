import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/core/storage/database/model_state_records.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/application/multimodal_llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/local_llm_engine.dart';
import 'package:note_secret_search/features/ai_models/application/model_lifecycle_controller.dart';
import 'package:note_secret_search/features/ai_models/application/model_session_releaser.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/io_model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/io_model_revision_store.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_source_probe_service.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:uuid/uuid.dart';

part 'model_download_sensitive_providers.dart';
part 'model_download_controller_internals.dart';
part 'model_download_dependencies.dart';
part 'model_download_structured.dart';
part 'model_download_structured_support.dart';

class ModelDownloadController {
  ModelDownloadController({
    required Ref ref,
    required ModelDownloadRepository repository,
    required ModelRegistryRepository registryRepository,
    required ModelDownloadService downloadService,
    required ModelLifecycleStore lifecycleStore,
    required ModelArtifactStore artifactStore,
    required AppLogger logger,
    ModelRevisionStore? revisionStore,
    ModelInstallJournalStore? installJournalStore,
    ModelSessionReleaser? sessionReleaser,
  }) : _ref = ref,
       _repository = repository,
       _registryRepository = registryRepository,
       _downloadService = downloadService,
       _lifecycleStore = lifecycleStore,
       _revisionStore = revisionStore ?? IoModelRevisionStore(),
       _installJournalStore =
           installJournalStore ??
           (lifecycleStore is ModelInstallJournalStore
               ? lifecycleStore as ModelInstallJournalStore
               : null),
       _modelLifecycleController = ModelLifecycleController(
         lifecycleStore: lifecycleStore,
         artifactStore: artifactStore,
         sessionReleaser:
             sessionReleaser ??
             ModelSessionReleaser(
               stopWrites: ref.read(searchIndexWriteFenceProvider).invalidate,
               releaseEmbedding: (modelId) {
                 return ref
                     .read(embeddingRuntimeBridgeProvider)
                     .releaseModel(modelId: modelId);
               },
               releaseLlm: (modelId) {
                 return ref
                     .read(llmRuntimeBridgeProvider)
                     .releaseModel(modelId: modelId);
               },
               shouldReleaseEmbedding: (modelType) =>
                   modelType == null || modelType == 'embedding',
               shouldReleaseLlm: (modelType) =>
                   modelType == null ||
                   modelType == 'llm' ||
                   modelType == 'multimodal_llm',
               shouldReleaseMultimodal: (modelType) =>
                   modelType == null || modelType == 'multimodal_llm',
             ),
         invalidateEmbeddingWrites: ref
             .read(searchIndexWriteFenceProvider)
             .invalidate,
         releaseEmbeddingModel: (modelId) {
           return ref
               .read(embeddingRuntimeBridgeProvider)
               .releaseModel(modelId: modelId);
         },
       ),
       _logger = logger;

  final Ref _ref;
  final ModelDownloadRepository _repository;
  final ModelRegistryRepository _registryRepository;
  final ModelDownloadService _downloadService;
  final ModelLifecycleStore _lifecycleStore;
  final ModelRevisionStore _revisionStore;
  final ModelInstallJournalStore? _installJournalStore;
  final ModelLifecycleController _modelLifecycleController;
  final AppLogger _logger;
  final Map<String, Future<void>> _modelOperationLocks =
      <String, Future<void>>{};
  final Map<String, int> _modelGenerations = <String, int>{};
  final Map<String, String> _activeOperationIds = <String, String>{};
  static const _uuid = Uuid();

  Future<void> enqueueDownload({
    required String modelId,
    required String sourceId,
    required int? totalBytes,
  }) async {
    final existing = await _repository.findLatestTaskByModelAndSource(
      modelId,
      sourceId,
    );
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
      throw UnsupportedError(
        '当前版本尚不支持 ${entry.type} 模型下载部署；需要专用 runtime 后才能安装。',
      );
    }

    if (entry.type == 'multimodal_llm') {
      await _startMultimodalDownload(entry: entry);
      return;
    }
    if (entry.artifacts.isNotEmpty) {
      await _startStructuredDownload(entry: entry, source: source);
      return;
    }

    ModelRegistryEntry? existingRegistry = await _registryRepository.getById(
      entry.id,
    );
    if (existingRegistry != null) {
      final normalizedEntries = await _ref.read(
        modelRegistryEntriesProvider.future,
      );
      existingRegistry =
          normalizedEntries.where((item) => item.id == entry.id).firstOrNull ??
          existingRegistry;

      final filePresent = await _downloadService.fileExists(
        existingRegistry.localPath,
      );
      if (existingRegistry.isInstalled && filePresent) {
        _ref.invalidate(modelRegistryEntriesProvider);
        return;
      }
      await _modelLifecycleController.prepareForMutation(
        existingRegistry.id,
        modelType: existingRegistry.type,
      );
      if (filePresent) {
        await _downloadService.deleteLocalFile(existingRegistry.localPath);
      }
    }

    final candidates = await _orderedCandidateSources(
      entry: entry,
      selectedSource: source,
    );

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
        final existingTask = await _repository.findLatestTaskByModelAndSource(
          entry.id,
          source.id,
        );
        final taskForAdoption =
            existingTask ??
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

      final task = await _repository.findLatestTaskByModelAndSource(
        entry.id,
        candidate.id,
      );
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
            final current = await _repository.findLatestTaskByModelAndSource(
              entry.id,
              candidate.id,
            );
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
        _logger.error('model_download_failed', error, stackTrace);
        final hasFallback = index < candidates.length - 1;
        final eligibleForFailover = hasFallback && _isFailoverEligible(error);
        final message = eligibleForFailover
            ? '当前来源失败，正在尝试其他下载源：$error'
            : (candidates.length > 1 ? '所有可用下载源均失败：$error' : error.toString());
        await markFailedForSource(
          entry.id,
          sourceId: candidate.id,
          message: message,
        );
        if (!eligibleForFailover) {
          return;
        }
      }
    }
  }

  Future<void> pause(String modelId, {required String sourceId}) async {
    final task = await _repository.findLatestTaskByModelAndSource(
      modelId,
      sourceId,
    );
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
    await _modelLifecycleController.deleteInstalledModel(modelId);

    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(modelDownloadTasksProvider);
    _ref.invalidate(embeddingRuntimeStatesProvider);
    _ref.invalidate(llmRuntimeStatesProvider);
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

  Future<void> markFailedForSource(
    String modelId, {
    required String sourceId,
    required String message,
  }) async {
    final task = await _repository.findLatestTaskByModelAndSource(
      modelId,
      sourceId,
    );
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
    _logger.info('model_revalidation_started');
    final entry = await _registryRepository.getById(modelId);
    if (entry == null) {
      _logger.warning('model_revalidation_missing_entry');
      return;
    }

    var normalized = await _normalizeRegistryEntry(entry);
    _logger.info('model_revalidation_state_checked');
    if (normalized.filePresent &&
        normalized.integrityStatus == ModelIntegrityStatus.valid) {
      if (normalized.type == 'llm' &&
          normalized.localPath != null &&
          normalized.localPath!.trim().isNotEmpty) {
        _logger.info('model_revalidation_runtime_check_started');
        final runtimeResult = await _ref
            .read(llmRuntimeBridgeProvider)
            .ensureModelReady(
              modelId: normalized.id,
              modelPath: normalized.localPath!,
            );
        final runtimeState = mapLlmRuntimeState(
          runtimeResult,
          fallbackPath: normalized.localPath,
        );
        _logger.info('model_revalidation_runtime_check_finished');
        normalized = normalized.copyWith(
          enabled:
              runtimeState.status == LlmRuntimeStatus.ready ||
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
      _logger.info('model_revalidation_saved');
    }

    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(embeddingRuntimeStatesProvider);
    _ref.invalidate(llmRuntimeStatesProvider);
    _logger.info('model_revalidation_invalidated');
  }

  /// Repairs a broken installed model by re-downloading it from the catalog.
  /// Uses the built-in catalog entry for the model and the first available source.
  /// If no matching catalog entry or no sources exist, this is a no-op.
  Future<void> repairInstalledModel(String modelId) async {
    final catalogEntries = await _ref.read(modelCatalogEntriesProvider.future);
    final catalogEntry = catalogEntries
        .where((e) => e.id == modelId)
        .firstOrNull;

    if (catalogEntry == null || catalogEntry.sources.isEmpty) {
      return;
    }

    final firstSource = catalogEntry.sources.first;
    await startDownload(entry: catalogEntry, source: firstSource);
  }

  /// Normalizes a [ModelRegistryEntry] by checking file presence and checksum,
  /// returning an updated entry with corrected [filePresent], [enabled], and
  /// [integrityStatus]. Does NOT persist — caller decides when to save.
}
