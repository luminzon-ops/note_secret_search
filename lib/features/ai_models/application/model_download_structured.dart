part of 'model_download_providers.dart';

extension _StructuredModelDownload on ModelDownloadController {
  Future<void> _startStructuredDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
    String? operationType,
  }) async {
    final previous = _modelOperationLocks[entry.id];
    late final Future<void> current;
    current = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // A failed operation must not permanently block a later retry.
        }
      }
      final operation = await _beginStructuredOperation(
        entry,
        requestedOperationType: operationType,
      );
      _activeOperationIds[entry.id] = operation.operationId;
      try {
        await _performStructuredDownload(
          entry: entry,
          selectedSource: source,
          operation: operation,
        );
      } finally {
        if (_activeOperationIds[entry.id] == operation.operationId) {
          _activeOperationIds.remove(entry.id);
        }
        if (identical(_modelOperationLocks[entry.id], current)) {
          _modelOperationLocks.remove(entry.id);
        }
      }
    }();
    _modelOperationLocks[entry.id] = current;
    return current;
  }

  Future<_StructuredOperation> _beginStructuredOperation(
    ModelCatalogEntry entry, {
    String? requestedOperationType,
  }) async {
    final modelId = entry.id;
    final existing = await _registryRepository.getById(modelId);
    final operationType =
        requestedOperationType ?? (existing == null ? 'install' : 'replace');
    final latestTask = await _repository.findLatestTaskByModel(modelId);
    final journalStore = _installJournalStore;
    var openJournals = const <ModelInstallJournalRecord>[];
    if (journalStore != null) {
      openJournals = await journalStore.listOpenInstallJournals();
      final resumable = await _findResumableStructuredJournal(
        entry: entry,
        journals: openJournals,
        operationType: operationType,
      );
      if (resumable != null) {
        _modelGenerations[modelId] = _maxInt(
          _modelGenerations[modelId] ?? 0,
          resumable.attemptGeneration,
        );
        return _StructuredOperation(
          operationId: resumable.operationId,
          generation: resumable.attemptGeneration,
          createdAt: resumable.createdAt,
          resuming: true,
          operationType: resumable.operationType,
        );
      }
    }
    var generation = _modelGenerations[modelId] ?? 0;
    generation = _maxInt(generation, existing?.generation ?? 0);
    generation = _maxInt(generation, latestTask?.attemptGeneration ?? 0);
    for (final journal in openJournals) {
      if (journal.modelId == modelId) {
        generation = _maxInt(generation, journal.attemptGeneration);
      }
    }
    generation += 1;
    _modelGenerations[modelId] = generation;
    return _StructuredOperation(
      operationId: ModelDownloadController._uuid.v4(),
      generation: generation,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      resuming: false,
      operationType: operationType,
    );
  }

  Future<void> _performStructuredDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry selectedSource,
    required _StructuredOperation operation,
  }) async {
    final tasks = <ModelDownloadTask>[];
    final staged = <String, _StagedStructuredArtifact>{};
    final existing = await _registryRepository.getById(entry.id);
    final verifiedExisting =
        operation.operationType == 'repair' && existing != null
        ? await _integrityVerifier.verify(existing)
        : existing;
    try {
      await _recoverStructuredJournals(
        entry.id,
        excludedOperationId: operation.resuming ? operation.operationId : null,
      );
      if (!operation.resuming) {
        await _recordStructuredJournal(
          entry: entry,
          operation: operation,
          existing: existing,
          phase: 'queued',
        );
      }
      await _revisionStore.recoverInterruptedInstalls(modelId: entry.id);
      await _recordStructuredJournal(
        entry: entry,
        operation: operation,
        existing: existing,
        phase: 'staging',
      );
      for (final artifact in entry.artifacts) {
        final reusable = verifiedExisting == null
            ? null
            : await _stageReusableInstalledArtifact(
                entry: entry,
                artifact: artifact,
                existing: verifiedExisting,
                operation: operation,
              );
        final result =
            reusable ??
            (artifact.isBundledAsset
                ? await _stageBundledArtifact(
                    entry: entry,
                    artifact: artifact,
                    operation: operation,
                  )
                : await _stageDownloadedArtifact(
                    entry: entry,
                    artifact: artifact,
                    selectedSource: selectedSource,
                    operation: operation,
                  ));
        tasks.add(result.task);
        staged[artifact.id] = result;
      }

      await _recordStructuredJournal(
        entry: entry,
        operation: operation,
        existing: existing,
        phase: 'staged',
      );
      await _recordStructuredJournal(
        entry: entry,
        operation: operation,
        existing: existing,
        phase: 'runtime_validating',
      );
      final runtime = await _validateStructuredRuntime(
        entry: entry,
        staged: staged,
      );
      await _recordStructuredJournal(
        entry: entry,
        operation: operation,
        existing: existing,
        phase: 'releasing_sessions',
      );
      await _modelLifecycleController.prepareForMutation(
        entry.id,
        modelType: existing?.type ?? entry.type,
      );
      await _recordStructuredJournal(
        entry: entry,
        operation: operation,
        existing: existing,
        phase: 'installing',
      );
      final installed = await _revisionStore.installVerifiedRevision(
        modelId: entry.id,
        operationId: operation.operationId,
        generation: operation.generation,
        artifacts: staged.values
            .map((item) => item.staged)
            .toList(growable: false),
      );
      final registryEntry = _buildStructuredRegistryEntry(
        entry: entry,
        operation: operation,
        staged: staged,
        installed: installed,
        enabled: runtime.enabled,
      );
      await _recordStructuredJournal(
        entry: entry,
        operation: operation,
        existing: existing,
        phase: 'committing',
      );
      final completedTasks = tasks
          .map(
            (task) => task.copyWith(
              status: ModelDownloadStatus.completed,
              phase: ModelDownloadPhase.completed,
              downloadedBytes: task.expectedSizeBytes ?? task.downloadedBytes,
              receivedBytes:
                  task.expectedSizeBytes ?? task.effectiveReceivedBytes,
              updatedAt: DateTime.now(),
            ),
          )
          .toList(growable: false);
      try {
        await _lifecycleStore.commitInstallation(
          registryEntry: registryEntry,
          completedTasks: completedTasks,
        );
      } catch (_) {
        await _revisionStore.discardInstalledRevision(
          modelId: entry.id,
          revisionRoot: installed.revisionRoot,
        );
        rethrow;
      }
      await _recordStructuredJournal(
        entry: entry,
        operation: operation,
        existing: existing,
        phase: 'completed',
        completed: true,
      );
      await _discardPreviousRevision(
        entry: entry,
        existing: existing,
        operation: operation,
      );
      _ref.invalidate(modelDownloadTasksProvider);
      _ref.invalidate(modelRegistryEntriesProvider);
      _ref.invalidate(embeddingRuntimeStatesProvider);
      _ref.invalidate(llmRuntimeStatesProvider);
    } on _StructuredDownloadPaused {
      _logger.info('structured_model_download_paused');
      _ref.invalidate(modelDownloadTasksProvider);
    } catch (error, stackTrace) {
      _logger.error('structured_model_download_failed', error, stackTrace);
      await _tryRecordStructuredFailure(
        entry: entry,
        operation: operation,
        existing: existing,
      );
      await _markStructuredTasksFailed(tasks, error.toString());
    }
  }

  Future<_StagedStructuredArtifact?> _stageReusableInstalledArtifact({
    required ModelCatalogEntry entry,
    required ModelArtifactSpec artifact,
    required ModelRegistryEntry existing,
    required _StructuredOperation operation,
  }) async {
    if (operation.operationType != 'repair' ||
        existing.releaseId != entry.releaseId) {
      return null;
    }
    final installed = existing.artifactById(artifact.id);
    if (installed == null ||
        !installed.isVerified ||
        installed.releaseId != artifact.releaseId ||
        installed.role != artifact.role ||
        installed.required != artifact.required ||
        installed.relativePath != artifact.relativePath ||
        installed.effectiveExpectedChecksum != artifact.checksum ||
        installed.effectiveExpectedSizeBytes != artifact.sizeBytes) {
      return null;
    }

    late final String sourceId;
    late final String sourceUrl;
    if (artifact.isBundledAsset) {
      sourceId = 'asset-${artifact.id}';
      sourceUrl = 'asset:${artifact.relativePath}';
    } else {
      final source = artifact.sources
          .where((candidate) => candidate.id == installed.sourceId)
          .firstOrNull;
      if (source == null) {
        return null;
      }
      sourceId = source.id;
      sourceUrl = source.url;
    }

    final staged = await _revisionStore.stageExistingArtifact(
      modelId: entry.id,
      operationId: operation.operationId,
      artifactId: artifact.id,
      relativePath: artifact.relativePath,
      sourcePath: installed.localPath,
      expectedSizeBytes: artifact.sizeBytes,
      expectedChecksum: artifact.checksum,
    );
    final now = DateTime.now();
    final task =
        _newStructuredTask(
          entry: entry,
          artifact: artifact,
          sourceId: sourceId,
          sourceUrl: sourceUrl,
          stagingPath: staged.stagingPath,
          operation: operation,
          resumable: false,
        ).copyWith(
          phase: ModelDownloadPhase.staged,
          downloadedBytes: artifact.sizeBytes,
          receivedBytes: artifact.sizeBytes,
          totalBytes: artifact.sizeBytes,
          updatedAt: now,
        );
    await _repository.saveTask(task);
    return _StagedStructuredArtifact(
      artifact: artifact,
      staged: staged,
      sourceId: sourceId,
      task: task,
    );
  }

  Future<_StagedStructuredArtifact> _stageDownloadedArtifact({
    required ModelCatalogEntry entry,
    required ModelArtifactSpec artifact,
    required ModelSourceEntry selectedSource,
    required _StructuredOperation operation,
  }) async {
    final target = await _downloadService.resolveArtifactStagingTarget(
      modelId: entry.id,
      operationId: operation.operationId,
      artifactId: artifact.id,
    );
    var task = await _findStructuredTask(
      operationId: operation.operationId,
      generation: operation.generation,
      artifactId: artifact.id,
    );
    if (task != null &&
        !_structuredTaskMatchesArtifact(
          task: task,
          entry: entry,
          artifact: artifact,
          operation: operation,
          stagingPath: target.stagingPath,
        )) {
      throw StateError('structured_resume_identity_mismatch');
    }
    final reused = await _reuseStagedStructuredArtifact(
      entry: entry,
      artifact: artifact,
      task: task,
    );
    if (reused != null) {
      return reused;
    }
    final candidates = _orderedArtifactSources(
      artifact: artifact,
      selectedSource: selectedSource,
      preferredSourceId: task?.sourceId,
    );
    Object? lastError;
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      if (candidate.checksum != artifact.checksum) {
        throw StateError('artifact_source_digest_mismatch');
      }
      final prepared = await _prepareStructuredTask(
        entry: entry,
        artifact: artifact,
        operation: operation,
        sourceId: candidate.id,
        sourceUrl: candidate.url,
        stagingPath: target.stagingPath,
        sourceResumable: true,
        existing: task,
      );
      final activeTask = prepared.task;
      task = activeTask;
      try {
        final result = await _downloadService.stageArtifact(
          taskId: activeTask.id,
          modelId: entry.id,
          operationId: operation.operationId,
          artifactId: artifact.id,
          sourceUrl: candidate.url,
          expectedChecksum: artifact.checksum,
          expectedSizeBytes: artifact.sizeBytes,
          resumeFromBytes: prepared.resumeFromBytes,
          onProgress: (progress) => _saveStructuredProgress(
            task: activeTask,
            progress: progress,
            operation: operation,
          ),
        );
        final completed = activeTask.copyWith(
          status: ModelDownloadStatus.downloading,
          phase: ModelDownloadPhase.staged,
          downloadedBytes: result.totalBytes,
          receivedBytes: result.totalBytes,
          totalBytes: result.totalBytes,
          stagingPath: result.localPath,
          etag: result.etag,
          lastModified: result.lastModified,
          resumable: result.resumable,
          updatedAt: DateTime.now(),
        );
        await _repository.saveTask(completed);
        return _StagedStructuredArtifact(
          artifact: artifact,
          staged: StagedModelArtifact(
            artifactId: artifact.id,
            relativePath: artifact.relativePath,
            stagingPath: result.localPath,
            expectedSizeBytes: artifact.sizeBytes,
            expectedChecksum: artifact.checksum,
          ),
          sourceId: candidate.id,
          task: completed,
        );
      } catch (error) {
        lastError = error;
        task =
            await _findStructuredTask(
              operationId: operation.operationId,
              generation: operation.generation,
              artifactId: artifact.id,
            ) ??
            task;
        if (_isStructuredPause(error, task)) {
          throw const _StructuredDownloadPaused();
        }
        final canFailover =
            _isFailoverEligible(error) && index < candidates.length - 1;
        await _repository.saveTask(
          task.copyWith(
            status: ModelDownloadStatus.failed,
            phase: canFailover
                ? ModelDownloadPhase.retryableFailed
                : ModelDownloadPhase.failed,
            errorMessage: error.toString(),
            retryReason: error.toString(),
            updatedAt: _nextTaskTimestamp(task.updatedAt),
          ),
        );
        if (!canFailover) {
          rethrow;
        }
      }
    }
    throw StateError(lastError?.toString() ?? 'artifact_source_missing');
  }

  Future<_StagedStructuredArtifact> _stageBundledArtifact({
    required ModelCatalogEntry entry,
    required ModelArtifactSpec artifact,
    required _StructuredOperation operation,
  }) async {
    final sourceId = 'asset-${artifact.id}';
    final sourceUrl = 'asset:${artifact.relativePath}';
    final target = await _downloadService.resolveArtifactStagingTarget(
      modelId: entry.id,
      operationId: operation.operationId,
      artifactId: artifact.id,
    );
    var task = await _findStructuredTask(
      operationId: operation.operationId,
      generation: operation.generation,
      artifactId: artifact.id,
    );
    if (task != null &&
        !_structuredTaskMatchesArtifact(
          task: task,
          entry: entry,
          artifact: artifact,
          operation: operation,
          stagingPath: target.stagingPath,
        )) {
      throw StateError('structured_resume_identity_mismatch');
    }
    final reused = await _reuseStagedStructuredArtifact(
      entry: entry,
      artifact: artifact,
      task: task,
    );
    if (reused != null) {
      return reused;
    }
    final prepared = await _prepareStructuredTask(
      entry: entry,
      artifact: artifact,
      operation: operation,
      sourceId: sourceId,
      sourceUrl: sourceUrl,
      stagingPath: target.stagingPath,
      sourceResumable: false,
      existing: task,
    );
    task = prepared.task;
    try {
      final data = await rootBundle.load(artifact.relativePath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.length != artifact.sizeBytes) {
        throw StateError('bundled_artifact_size_mismatch');
      }
      final file = File(target.stagingPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      final checksum = await _downloadService.verifyChecksum(
        filePath: file.path,
        expectedChecksum: artifact.checksum,
      );
      final completed = task.copyWith(
        status: ModelDownloadStatus.downloading,
        phase: ModelDownloadPhase.staged,
        downloadedBytes: bytes.length,
        receivedBytes: bytes.length,
        totalBytes: bytes.length,
        stagingPath: file.path,
        expectedChecksum: checksum,
        updatedAt: DateTime.now(),
      );
      await _repository.saveTask(completed);
      return _StagedStructuredArtifact(
        artifact: artifact,
        staged: StagedModelArtifact(
          artifactId: artifact.id,
          relativePath: artifact.relativePath,
          stagingPath: file.path,
          expectedSizeBytes: artifact.sizeBytes,
          expectedChecksum: artifact.checksum,
        ),
        sourceId: sourceId,
        task: completed,
      );
    } catch (error) {
      task =
          await _findStructuredTask(
            operationId: operation.operationId,
            generation: operation.generation,
            artifactId: artifact.id,
          ) ??
          task;
      await _repository.saveTask(
        task.copyWith(
          status: ModelDownloadStatus.failed,
          phase: ModelDownloadPhase.failed,
          errorMessage: error.toString(),
          updatedAt: _nextTaskTimestamp(task.updatedAt),
        ),
      );
      rethrow;
    }
  }
}
