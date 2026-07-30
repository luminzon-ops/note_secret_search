part of 'model_download_providers.dart';

extension _StructuredModelArtifactStaging on ModelDownloadController {
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
      final stagedAsset = await _bundledArtifactStager.stage(
        assetPath: artifact.relativePath,
        targetPath: target.stagingPath,
        expectedSizeBytes: artifact.sizeBytes,
      );
      final checksum = await _downloadService.verifyChecksum(
        filePath: stagedAsset.path,
        expectedChecksum: artifact.checksum,
      );
      final completed = task.copyWith(
        status: ModelDownloadStatus.downloading,
        phase: ModelDownloadPhase.staged,
        downloadedBytes: stagedAsset.sizeBytes,
        receivedBytes: stagedAsset.sizeBytes,
        totalBytes: stagedAsset.sizeBytes,
        stagingPath: stagedAsset.path,
        expectedChecksum: checksum,
        updatedAt: DateTime.now(),
      );
      await _repository.saveTask(completed);
      return _StagedStructuredArtifact(
        artifact: artifact,
        staged: StagedModelArtifact(
          artifactId: artifact.id,
          relativePath: artifact.relativePath,
          stagingPath: stagedAsset.path,
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
