part of 'model_download_providers.dart';

extension _StructuredModelDownloadSupport on ModelDownloadController {
  Future<void> _recoverStructuredJournals(String modelId) async {
    final store = _installJournalStore;
    if (store == null) {
      return;
    }
    final openJournals = await store.listOpenInstallJournals();
    final current = await _registryRepository.getById(modelId);
    for (final journal in openJournals) {
      if (journal.modelId != modelId) {
        continue;
      }
      _modelGenerations[modelId] = _maxInt(
        _modelGenerations[modelId] ?? 0,
        journal.attemptGeneration,
      );
      final target = journal.targetRoot ?? journal.newRevision;
      final committed =
          current?.isInstalled == true &&
          current?.generation == journal.attemptGeneration &&
          current?.releaseId == journal.releaseId &&
          current?.revisionRoot == target;
      if (committed) {
        await store.saveInstallJournal(
          _recoveredJournal(journal, phase: 'completed', completed: true),
        );
        final previous = journal.oldRevision;
        if (previous != null && previous != target) {
          try {
            await _revisionStore.discardInstalledRevision(
              modelId: modelId,
              revisionRoot: previous,
            );
          } catch (_) {
            _logger.warning('model_previous_revision_cleanup_deferred');
          }
        }
        continue;
      }
      if (target != null) {
        if (current?.revisionRoot == target) {
          await store.saveInstallJournal(
            _recoveredJournal(
              journal,
              phase: 'rollback_pending',
              errorCode: 'interrupted_install_registry_conflict',
            ),
          );
          throw StateError('interrupted_install_registry_conflict');
        }
        try {
          await _revisionStore.discardInstalledRevision(
            modelId: modelId,
            revisionRoot: target,
          );
        } catch (_) {
          await store.saveInstallJournal(
            _recoveredJournal(
              journal,
              phase: 'rollback_pending',
              errorCode: 'interrupted_install_cleanup_failed',
            ),
          );
          rethrow;
        }
      }
      await store.saveInstallJournal(
        _recoveredJournal(
          journal,
          phase: 'failed',
          completed: true,
          errorCode: 'interrupted_install_rolled_back',
        ),
      );
    }
  }

  Future<void> _recordStructuredJournal({
    required ModelCatalogEntry entry,
    required _StructuredOperation operation,
    required ModelRegistryEntry? existing,
    required String phase,
    bool completed = false,
    String? errorCode,
  }) async {
    final store = _installJournalStore;
    if (store == null) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.saveInstallJournal(
      ModelInstallJournalRecord(
        operationId: operation.operationId,
        modelId: entry.id,
        releaseId: entry.releaseId,
        attemptGeneration: operation.generation,
        operationType: existing == null ? 'install' : 'replace',
        phase: phase,
        oldRevision: existing?.revisionRoot,
        newRevision: 'revisions/${operation.generation}',
        stagingRoot: '.staging/${operation.operationId}',
        targetRoot: 'revisions/${operation.generation}',
        errorCode: errorCode,
        createdAt: operation.createdAt,
        updatedAt: now,
        completedAt: completed ? now : null,
      ),
    );
  }

  Future<void> _tryRecordStructuredFailure({
    required ModelCatalogEntry entry,
    required _StructuredOperation operation,
    required ModelRegistryEntry? existing,
  }) async {
    try {
      await _recordStructuredJournal(
        entry: entry,
        operation: operation,
        existing: existing,
        phase: 'failed',
        completed: true,
        errorCode: 'structured_install_failed',
      );
    } catch (error, stackTrace) {
      _logger.error('model_install_journal_failed', error, stackTrace);
    }
  }

  Future<void> _discardPreviousRevision({
    required ModelCatalogEntry entry,
    required ModelRegistryEntry? existing,
    required _StructuredOperation operation,
  }) async {
    final previous = existing?.revisionRoot;
    if (previous == null || previous == 'revisions/${operation.generation}') {
      return;
    }
    try {
      await _revisionStore.discardInstalledRevision(
        modelId: entry.id,
        revisionRoot: previous,
      );
    } catch (_) {
      _logger.warning('model_previous_revision_cleanup_deferred');
    }
  }

  List<ModelSourceEntry> _orderedArtifactSources({
    required ModelArtifactSpec artifact,
    required ModelSourceEntry selectedSource,
  }) {
    final sources = artifact.sources.toList(growable: false);
    final selected = sources
        .where((candidate) => candidate.id == selectedSource.id)
        .firstOrNull;
    final ordered = <ModelSourceEntry>[];
    if (selected != null) {
      ordered.add(selected);
    }
    final remaining =
        sources
            .where((candidate) => candidate.id != selected?.id)
            .toList(growable: false)
          ..sort((a, b) => a.priority.compareTo(b.priority));
    ordered.addAll(remaining);
    return ordered;
  }

  ModelDownloadTask _newStructuredTask({
    required ModelCatalogEntry entry,
    required ModelArtifactSpec artifact,
    required String sourceId,
    required String sourceUrl,
    required String stagingPath,
    required _StructuredOperation operation,
    bool resumable = true,
  }) {
    final now = DateTime.now();
    return ModelDownloadTask(
      id: ModelDownloadController._uuid.v4(),
      modelId: entry.id,
      sourceId: sourceId,
      status: ModelDownloadStatus.downloading,
      totalBytes: artifact.sizeBytes,
      downloadedBytes: 0,
      averageSpeed: null,
      errorMessage: null,
      resumable: resumable,
      createdAt: now,
      updatedAt: now,
      operationId: operation.operationId,
      attemptGeneration: operation.generation,
      releaseId: artifact.releaseId,
      artifactId: artifact.id,
      sourceUrl: sourceUrl,
      stagingPath: stagingPath,
      expectedChecksum: artifact.checksum,
      expectedSizeBytes: artifact.sizeBytes,
      phase: ModelDownloadPhase.downloading,
      receivedBytes: 0,
    );
  }

  Future<void> _saveStructuredProgress({
    required ModelDownloadTask task,
    required ModelDownloadProgress progress,
    required _StructuredOperation operation,
  }) async {
    if (_activeOperationIds[task.modelId] != operation.operationId) {
      return;
    }
    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.downloading,
        phase: ModelDownloadPhase.downloading,
        totalBytes: progress.totalBytes ?? task.totalBytes,
        downloadedBytes: progress.receivedBytes,
        receivedBytes: progress.receivedBytes,
        averageSpeed: progress.averageSpeedBytesPerSecond,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<_StructuredRuntimeResult> _validateStructuredRuntime({
    required ModelCatalogEntry entry,
    required Map<String, _StagedStructuredArtifact> staged,
  }) async {
    final primary = entry.primaryArtifact;
    if (primary == null) {
      throw StateError('primary_artifact_missing');
    }
    final modelPath = staged[primary.id]!.staged.stagingPath;
    switch (entry.type) {
      case 'embedding':
        final result = await _ref
            .read(embeddingRuntimeBridgeProvider)
            .ensureModelReady(
              modelId: entry.id,
              modelPath: modelPath,
              tokenizer: entry.tokenizer,
              runtime: entry.runtime,
              verifiedChecksum: primary.checksum,
            );
        final state = mapEmbeddingEngineState(result, fallbackPath: modelPath);
        if (state.status != EmbeddingRuntimeStatus.ready &&
            state.status != EmbeddingRuntimeStatus.installedUnverified) {
          throw StateError('embedding_runtime_validation_failed');
        }
        return _StructuredRuntimeResult(
          enabled: state.status == EmbeddingRuntimeStatus.ready,
        );
      case 'llm':
        final result = await _ref
            .read(llmRuntimeBridgeProvider)
            .ensureModelReady(modelId: entry.id, modelPath: modelPath);
        final state = mapLlmRuntimeState(result, fallbackPath: modelPath);
        if (state.status != LlmRuntimeStatus.ready &&
            state.status != LlmRuntimeStatus.installedUnverified) {
          throw StateError('llm_runtime_validation_failed');
        }
        return _StructuredRuntimeResult(
          enabled: state.status == LlmRuntimeStatus.ready,
        );
      default:
        throw UnsupportedError('unsupported_structured_runtime');
    }
  }

  ModelRegistryEntry _buildStructuredRegistryEntry({
    required ModelCatalogEntry entry,
    required _StructuredOperation operation,
    required Map<String, _StagedStructuredArtifact> staged,
    required InstalledModelRevision installed,
    required bool enabled,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final artifacts = entry.artifacts
        .map(
          (artifact) => ModelArtifactPath(
            artifactId: artifact.id,
            releaseId: artifact.releaseId,
            role: artifact.role,
            required: artifact.required,
            relativePath: artifact.relativePath,
            localPath: installed.pathsByArtifactId[artifact.id]!,
            sourceId: staged[artifact.id]!.sourceId,
            expectedChecksum: artifact.checksum,
            expectedSizeBytes: artifact.sizeBytes,
            verifiedChecksum: artifact.checksum,
            verifiedSizeBytes: artifact.sizeBytes,
            state: 'installed',
            verifiedAt: now,
          ),
        )
        .toList(growable: false);
    final primary = artifacts.firstWhere(
      (artifact) => artifact.role == 'model',
    );
    return ModelRegistryEntry(
      id: entry.id,
      type: entry.type,
      provider: 'builtin_catalog',
      name: entry.displayName,
      version: entry.releaseId,
      sizeBytes: entry.artifacts.fold<int>(
        0,
        (sum, artifact) => sum + artifact.sizeBytes,
      ),
      quantization: null,
      minRamMb: entry.minRamMb,
      recommendedTier: entry.recommendedTier,
      localPath: primary.localPath,
      checksum: primary.effectiveExpectedChecksum,
      enabled: enabled,
      installedAt: DateTime.fromMillisecondsSinceEpoch(now),
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.valid,
      artifacts: artifacts,
      releaseId: entry.releaseId,
      catalogVersion: entry.catalogVersion,
      catalogDigest: entry.catalogDigest,
      generation: operation.generation,
      revisionRoot: 'revisions/${operation.generation}',
    );
  }

  Future<void> _markStructuredTasksFailed(
    List<ModelDownloadTask> tasks,
    String message,
  ) async {
    for (final task in tasks) {
      if (task.status == ModelDownloadStatus.failed) {
        continue;
      }
      await _repository.saveTask(
        task.copyWith(
          status: ModelDownloadStatus.failed,
          phase: ModelDownloadPhase.failed,
          errorMessage: message,
          retryReason: message,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }
}

int _maxInt(int first, int second) => first > second ? first : second;

ModelInstallJournalRecord _recoveredJournal(
  ModelInstallJournalRecord journal, {
  required String phase,
  bool completed = false,
  String? errorCode,
}) {
  final now = _maxInt(
    DateTime.now().millisecondsSinceEpoch,
    journal.updatedAt + 1,
  );
  return ModelInstallJournalRecord(
    operationId: journal.operationId,
    modelId: journal.modelId,
    releaseId: journal.releaseId,
    attemptGeneration: journal.attemptGeneration,
    operationType: journal.operationType,
    phase: phase,
    oldRevision: journal.oldRevision,
    newRevision: journal.newRevision,
    stagingRoot: journal.stagingRoot,
    targetRoot: journal.targetRoot,
    errorCode: errorCode,
    createdAt: journal.createdAt,
    updatedAt: now,
    completedAt: completed ? now : null,
  );
}
