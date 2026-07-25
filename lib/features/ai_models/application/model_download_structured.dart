part of 'model_download_providers.dart';

class _StructuredOperation {
  const _StructuredOperation({
    required this.operationId,
    required this.generation,
  });

  final String operationId;
  final int generation;
}

class _StagedStructuredArtifact {
  const _StagedStructuredArtifact({
    required this.artifact,
    required this.staged,
    required this.sourceId,
    required this.task,
  });

  final ModelArtifactSpec artifact;
  final StagedModelArtifact staged;
  final String sourceId;
  final ModelDownloadTask task;
}

class _StructuredRuntimeResult {
  const _StructuredRuntimeResult({required this.enabled});

  final bool enabled;
}

extension _StructuredModelDownload on ModelDownloadController {
  Future<void> _startStructuredDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
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
      final operation = await _beginStructuredOperation(entry.id);
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

  Future<_StructuredOperation> _beginStructuredOperation(String modelId) async {
    final existing = await _registryRepository.getById(modelId);
    final latestTask = await _repository.findLatestTaskByModel(modelId);
    var generation = _modelGenerations[modelId] ?? 0;
    generation = _maxInt(generation, existing?.generation ?? 0);
    generation = _maxInt(generation, latestTask?.attemptGeneration ?? 0) + 1;
    _modelGenerations[modelId] = generation;
    return _StructuredOperation(
      operationId: ModelDownloadController._uuid.v4(),
      generation: generation,
    );
  }

  Future<void> _performStructuredDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry selectedSource,
    required _StructuredOperation operation,
  }) async {
    final tasks = <ModelDownloadTask>[];
    final staged = <String, _StagedStructuredArtifact>{};
    try {
      await _revisionStore.recoverInterruptedInstalls(modelId: entry.id);
      for (final artifact in entry.artifacts) {
        final result = artifact.isBundledAsset
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
              );
        tasks.add(result.task);
        staged[artifact.id] = result;
      }

      final runtime = await _validateStructuredRuntime(
        entry: entry,
        staged: staged,
      );
      final existing = await _registryRepository.getById(entry.id);
      await _modelLifecycleController.prepareForMutation(
        entry.id,
        modelType: existing?.type ?? entry.type,
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
      _ref.invalidate(modelDownloadTasksProvider);
      _ref.invalidate(modelRegistryEntriesProvider);
      _ref.invalidate(embeddingRuntimeStatesProvider);
      _ref.invalidate(llmRuntimeStatesProvider);
    } catch (error, stackTrace) {
      _logger.error('structured_model_download_failed', error, stackTrace);
      await _markStructuredTasksFailed(tasks, error.toString());
    }
  }

  Future<_StagedStructuredArtifact> _stageDownloadedArtifact({
    required ModelCatalogEntry entry,
    required ModelArtifactSpec artifact,
    required ModelSourceEntry selectedSource,
    required _StructuredOperation operation,
  }) async {
    final candidates = _orderedArtifactSources(
      artifact: artifact,
      selectedSource: selectedSource,
    );
    Object? lastError;
    for (final candidate in candidates) {
      if (candidate.checksum != artifact.checksum) {
        throw StateError('artifact_source_digest_mismatch');
      }
      final target = await _downloadService.resolveArtifactStagingTarget(
        modelId: entry.id,
        operationId: operation.operationId,
        artifactId: artifact.id,
      );
      final task = _newStructuredTask(
        entry: entry,
        artifact: artifact,
        sourceId: candidate.id,
        sourceUrl: candidate.url,
        stagingPath: target.stagingPath,
        operation: operation,
      );
      await _repository.saveTask(task);
      try {
        final result = await _downloadService.stageArtifact(
          taskId: task.id,
          modelId: entry.id,
          operationId: operation.operationId,
          artifactId: artifact.id,
          sourceUrl: candidate.url,
          expectedChecksum: artifact.checksum,
          expectedSizeBytes: artifact.sizeBytes,
          onProgress: (progress) => _saveStructuredProgress(
            task: task,
            progress: progress,
            operation: operation,
          ),
        );
        final completed = task.copyWith(
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
        await _repository.saveTask(
          task.copyWith(
            status: ModelDownloadStatus.failed,
            phase: ModelDownloadPhase.retryableFailed,
            errorMessage: error.toString(),
            retryReason: error.toString(),
            updatedAt: DateTime.now(),
          ),
        );
        if (!_isFailoverEligible(error) || candidate == candidates.last) {
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
    final target = await _downloadService.resolveArtifactStagingTarget(
      modelId: entry.id,
      operationId: operation.operationId,
      artifactId: artifact.id,
    );
    final task = _newStructuredTask(
      entry: entry,
      artifact: artifact,
      sourceId: sourceId,
      sourceUrl: 'asset:${artifact.relativePath}',
      stagingPath: target.stagingPath,
      operation: operation,
      resumable: false,
    );
    await _repository.saveTask(task);
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
      await _repository.saveTask(
        task.copyWith(
          status: ModelDownloadStatus.failed,
          phase: ModelDownloadPhase.failed,
          errorMessage: error.toString(),
          updatedAt: DateTime.now(),
        ),
      );
      rethrow;
    }
  }
}
