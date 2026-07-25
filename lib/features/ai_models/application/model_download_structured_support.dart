part of 'model_download_providers.dart';

extension _StructuredModelDownloadSupport on ModelDownloadController {
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
