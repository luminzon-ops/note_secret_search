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
}
