part of 'model_download_providers.dart';

extension _LegacyModelDownloadCommands on ModelDownloadController {
  Future<void> _enqueueLegacyDownload({
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
      id: ModelDownloadController._uuid.v4(),
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

  Future<void> _markLegacyDownloading(String modelId) async {
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

  Future<void> _startLegacyDownload({
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
              id: ModelDownloadController._uuid.v4(),
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

  Future<void> _pauseLegacyDownload(
    String modelId, {
    required String sourceId,
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
        status: ModelDownloadStatus.paused,
        phase: task.operationId == null
            ? task.phase
            : ModelDownloadPhase.paused,
        updatedAt: _nextTaskTimestamp(task.updatedAt),
      ),
    );
    _downloadService.cancel(task.id);
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> _deleteLegacyInstalledModel(String modelId) async {
    await _modelLifecycleController.deleteInstalledModel(modelId);

    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(modelDownloadTasksProvider);
    _ref.invalidate(embeddingRuntimeStatesProvider);
  }

  Future<bool> _isLegacyInstalled(String modelId) async {
    final existing = await _registryRepository.getById(modelId);
    if (existing == null) {
      return false;
    }
    return _downloadService.fileExists(existing.localPath);
  }

  Future<void> _markLegacyFailed(String modelId, String message) async {
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

  Future<void> _markLegacyFailedForSource(
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

  Future<void> _markLegacyCompleted(String modelId) async {
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
}
