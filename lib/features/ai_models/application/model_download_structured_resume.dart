part of 'model_download_providers.dart';

class _StructuredOperation {
  const _StructuredOperation({
    required this.operationId,
    required this.generation,
    required this.createdAt,
    required this.resuming,
    required this.operationType,
  });

  final String operationId;
  final int generation;
  final int createdAt;
  final bool resuming;
  final String operationType;
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

class _StructuredDownloadPaused implements Exception {
  const _StructuredDownloadPaused();
}

extension _StructuredModelDownloadResume on ModelDownloadController {
  Future<ModelInstallJournalRecord?> _findResumableStructuredJournal({
    required ModelCatalogEntry entry,
    required List<ModelInstallJournalRecord> journals,
    required String operationType,
  }) async {
    final current = await _registryRepository.getById(entry.id);
    final candidates =
        journals
            .where(
              (journal) =>
                  journal.modelId == entry.id &&
                  journal.releaseId == entry.releaseId &&
                  journal.operationType == operationType &&
                  journal.oldRevision == current?.revisionRoot &&
                  (journal.phase == 'queued' || journal.phase == 'staging') &&
                  journal.attemptGeneration > 0 &&
                  journal.stagingRoot == '.staging/${journal.operationId}' &&
                  (journal.targetRoot ?? journal.newRevision) ==
                      'revisions/${journal.attemptGeneration}' &&
                  (_modelGenerations[entry.id] ?? 0) <=
                      journal.attemptGeneration,
            )
            .toList(growable: false)
          ..sort((a, b) {
            final generation = b.attemptGeneration.compareTo(
              a.attemptGeneration,
            );
            return generation != 0
                ? generation
                : b.updatedAt.compareTo(a.updatedAt);
          });
    if (candidates.isEmpty) {
      return null;
    }
    final tasks = await _repository.listTasks();
    for (final journal in candidates) {
      final operationTasks = tasks
          .where((task) => task.operationId == journal.operationId)
          .toList(growable: false);
      final artifactIds = <String>{};
      var valid = true;
      for (final task in operationTasks) {
        final artifact = entry.artifacts
            .where((candidate) => candidate.id == task.artifactId)
            .firstOrNull;
        if (artifact == null ||
            !artifactIds.add(artifact.id) ||
            task.phase == ModelDownloadPhase.completed ||
            task.phase == ModelDownloadPhase.failed) {
          valid = false;
          break;
        }
        final target = await _downloadService.resolveArtifactStagingTarget(
          modelId: entry.id,
          operationId: journal.operationId,
          artifactId: artifact.id,
        );
        if (!_structuredTaskMatchesArtifact(
          task: task,
          entry: entry,
          artifact: artifact,
          operation: _StructuredOperation(
            operationId: journal.operationId,
            generation: journal.attemptGeneration,
            createdAt: journal.createdAt,
            resuming: true,
            operationType: journal.operationType,
          ),
          stagingPath: target.stagingPath,
        )) {
          valid = false;
          break;
        }
      }
      if (valid) {
        return journal;
      }
    }
    return null;
  }

  Future<ModelDownloadTask?> _findStructuredTask({
    required String operationId,
    required int generation,
    required String artifactId,
  }) async {
    final tasks = await _repository.listTasks();
    final matching =
        tasks
            .where(
              (task) =>
                  task.operationId == operationId &&
                  task.attemptGeneration == generation &&
                  task.artifactId == artifactId,
            )
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matching.firstOrNull;
  }

  bool _structuredTaskMatchesArtifact({
    required ModelDownloadTask task,
    required ModelCatalogEntry entry,
    required ModelArtifactSpec artifact,
    required _StructuredOperation operation,
    required String stagingPath,
  }) {
    if (task.modelId != entry.id ||
        task.operationId != operation.operationId ||
        task.attemptGeneration != operation.generation ||
        task.releaseId != artifact.releaseId ||
        task.artifactId != artifact.id ||
        task.stagingPath != stagingPath ||
        task.expectedChecksum != artifact.checksum ||
        task.expectedSizeBytes != artifact.sizeBytes) {
      return false;
    }
    if (artifact.isBundledAsset) {
      return task.sourceId == 'asset-${artifact.id}' &&
          task.sourceUrl == 'asset:${artifact.relativePath}';
    }
    return artifact.sources.any(
      (source) =>
          source.id == task.sourceId &&
          source.url == task.sourceUrl &&
          source.checksum == artifact.checksum,
    );
  }

  Future<_StagedStructuredArtifact?> _reuseStagedStructuredArtifact({
    required ModelCatalogEntry entry,
    required ModelArtifactSpec artifact,
    required ModelDownloadTask? task,
  }) async {
    if (task == null ||
        task.phase != ModelDownloadPhase.staged ||
        task.stagingPath == null ||
        task.effectiveReceivedBytes != artifact.sizeBytes) {
      return null;
    }
    final stagingPath = task.stagingPath!;
    try {
      if (!await _downloadService.fileExists(stagingPath) ||
          await _downloadService.fileLength(stagingPath) !=
              artifact.sizeBytes) {
        return null;
      }
      await _downloadService.verifyChecksum(
        filePath: stagingPath,
        expectedChecksum: artifact.checksum,
      );
      return _StagedStructuredArtifact(
        artifact: artifact,
        staged: StagedModelArtifact(
          artifactId: artifact.id,
          relativePath: artifact.relativePath,
          stagingPath: stagingPath,
          expectedSizeBytes: artifact.sizeBytes,
          expectedChecksum: artifact.checksum,
        ),
        sourceId: task.sourceId,
        task: task,
      );
    } on Object {
      return null;
    }
  }

  Future<({ModelDownloadTask task, int resumeFromBytes})>
  _prepareStructuredTask({
    required ModelCatalogEntry entry,
    required ModelArtifactSpec artifact,
    required _StructuredOperation operation,
    required String sourceId,
    required String sourceUrl,
    required String stagingPath,
    required bool sourceResumable,
    ModelDownloadTask? existing,
  }) async {
    var task = existing;
    if (task == null) {
      task = _newStructuredTask(
        entry: entry,
        artifact: artifact,
        sourceId: sourceId,
        sourceUrl: sourceUrl,
        stagingPath: stagingPath,
        operation: operation,
        resumable: sourceResumable,
      );
      await _repository.saveTask(task);
      return (task: task, resumeFromBytes: 0);
    }
    if (!_structuredTaskMatchesArtifact(
      task: task,
      entry: entry,
      artifact: artifact,
      operation: operation,
      stagingPath: stagingPath,
    )) {
      throw StateError('structured_resume_identity_mismatch');
    }
    final sameSource = task.sourceId == sourceId && task.sourceUrl == sourceUrl;
    final resumeFromBytes = sameSource && _canResumeStructuredTask(task)
        ? task.effectiveReceivedBytes
        : 0;
    final needsReset =
        !sameSource ||
        task.phase == ModelDownloadPhase.staged ||
        (task.effectiveReceivedBytes > 0 && resumeFromBytes == 0);
    if (needsReset) {
      if (task.phase != ModelDownloadPhase.retryableFailed) {
        task = task.copyWith(
          status: ModelDownloadStatus.failed,
          phase: ModelDownloadPhase.retryableFailed,
          errorMessage: 'structured_download_restart_required',
          retryReason: 'structured_download_restart_required',
          updatedAt: _nextTaskTimestamp(task.updatedAt),
        );
        await _repository.saveTask(task);
      }
      task = task.copyWith(
        sourceId: sourceId,
        sourceUrl: sourceUrl,
        status: ModelDownloadStatus.downloading,
        phase: ModelDownloadPhase.downloading,
        downloadedBytes: 0,
        receivedBytes: 0,
        resumable: sourceResumable,
        clearAverageSpeed: true,
        clearErrorMessage: true,
        clearRetryReason: true,
        clearEtag: true,
        clearLastModified: true,
        updatedAt: _nextTaskTimestamp(task.updatedAt),
      );
      await _repository.saveTask(task);
      return (task: task, resumeFromBytes: 0);
    }
    task = task.copyWith(
      status: ModelDownloadStatus.downloading,
      phase: ModelDownloadPhase.downloading,
      downloadedBytes: resumeFromBytes,
      receivedBytes: resumeFromBytes,
      resumable: sourceResumable,
      clearErrorMessage: true,
      clearRetryReason: true,
      updatedAt: _nextTaskTimestamp(task.updatedAt),
    );
    await _repository.saveTask(task);
    return (task: task, resumeFromBytes: resumeFromBytes);
  }

  bool _canResumeStructuredTask(ModelDownloadTask task) {
    final received = task.effectiveReceivedBytes;
    final expected = task.expectedSizeBytes ?? task.totalBytes ?? 0;
    return task.resumable &&
        received > 0 &&
        received < expected &&
        _downloadService.isResumableValidator(
          etag: task.etag,
          lastModified: task.lastModified,
        );
  }

  bool _isStructuredPause(Object error, ModelDownloadTask task) {
    return task.status == ModelDownloadStatus.paused ||
        task.phase == ModelDownloadPhase.paused ||
        _downloadService.isCancellation(error);
  }
}

DateTime _nextTaskTimestamp(DateTime previous) {
  final now = DateTime.now();
  return now.isAfter(previous)
      ? now
      : previous.add(const Duration(milliseconds: 1));
}
