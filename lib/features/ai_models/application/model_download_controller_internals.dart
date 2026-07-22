part of 'model_download_providers.dart';

extension _ModelDownloadControllerInternals on ModelDownloadController {
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
      final matched = fallbackSources
          .where((source) => source.id == sourceId)
          .firstOrNull;
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
    return entry.type == 'embedding' || entry.type == 'llm';
  }

  Future<void> _startMultimodalDownload({
    required ModelCatalogEntry entry,
  }) async {
    final requiredSources = entry.sources
        .where((source) => source.required)
        .toList(growable: false);
    final results = <ModelSourceEntry, ModelDownloadResult>{};

    for (final source in requiredSources) {
      await enqueueDownload(
        modelId: entry.id,
        sourceId: source.id,
        totalBytes: null,
      );

      final task = await _repository.findLatestTaskByModelAndSource(
        entry.id,
        source.id,
      );
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
            final current = await _repository.findLatestTaskByModelAndSource(
              entry.id,
              source.id,
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
        results[source] = result;
        final current =
            await _repository.findLatestTaskByModelAndSource(
              entry.id,
              source.id,
            ) ??
            task;
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
        _logger.error('multimodal_model_download_failed', error, stackTrace);
        await markFailedForSource(
          entry.id,
          sourceId: source.id,
          message: error.toString(),
        );
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
    for (final MapEntry<ModelSourceEntry, ModelDownloadResult> item
        in results.entries) {
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

    final totalBytes = artifacts.fold<int>(
      0,
      (sum, artifact) => sum + (artifact.sizeBytes ?? 0),
    );
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
        checksum: artifacts
            .map((artifact) => '${artifact.role}:${artifact.checksum ?? ''}')
            .join('|'),
        enabled: true,
        installedAt: DateTime.now(),
        filePresent: true,
        integrityStatus: ModelIntegrityStatus.valid,
        artifacts: artifacts,
      ),
    );

    final runtimeResult = await _ref
        .read(multimodalLlmRuntimeBridgeProvider)
        .ensureModelReady(
          modelId: entry.id,
          modelPath: modelPath,
          mmprojPath: mmprojPath,
        );
    final ready =
        runtimeResult['ready'] == true || runtimeResult['status'] == 'ready';
    final persisted = await _registryRepository.getById(entry.id);
    if (persisted != null) {
      await _registryRepository.save(
        persisted.copyWith(enabled: ready, filePresent: true),
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
    final now = DateTime.now();
    final completedTask = task.copyWith(
      status: ModelDownloadStatus.completed,
      downloadedBytes: result.totalBytes,
      totalBytes: result.totalBytes,
      updatedAt: now,
      errorMessage: null,
      clearErrorMessage: true,
    );
    final registryEntry = await _validatedRegistryEntry(
      catalogEntry: entry,
      result: result,
      installedAt: now,
    );
    await _lifecycleStore.commitInstallation(
      registryEntry: registryEntry,
      completedTasks: <ModelDownloadTask>[completedTask],
    );

    _ref.invalidate(modelDownloadTasksProvider);
    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(embeddingRuntimeStatesProvider);
    _ref.invalidate(llmRuntimeStatesProvider);
  }

  Future<ModelRegistryEntry> _validatedRegistryEntry({
    required ModelCatalogEntry catalogEntry,
    required ModelDownloadResult result,
    required DateTime installedAt,
  }) async {
    var registryEntry = ModelRegistryEntry(
      id: catalogEntry.id,
      type: catalogEntry.type,
      provider: 'builtin_catalog',
      name: catalogEntry.displayName,
      version: null,
      sizeBytes: result.totalBytes,
      quantization: null,
      minRamMb: catalogEntry.minRamMb,
      recommendedTier: catalogEntry.recommendedTier,
      localPath: result.localPath,
      checksum: result.verifiedChecksum,
      enabled: true,
      installedAt: installedAt,
      filePresent: true,
      integrityStatus: ModelIntegrityStatus.valid,
    );

    if (catalogEntry.type == 'embedding') {
      final runtimeResult = await _ref
          .read(embeddingRuntimeBridgeProvider)
          .ensureModelReady(
            modelId: catalogEntry.id,
            modelPath: result.localPath,
            tokenizer: catalogEntry.tokenizer,
            runtime: catalogEntry.runtime,
            verifiedChecksum: result.verifiedChecksum,
          );
      final runtimeState = mapEmbeddingEngineState(
        runtimeResult,
        fallbackPath: result.localPath,
      );
      registryEntry = registryEntry.copyWith(
        enabled:
            runtimeState.status == EmbeddingRuntimeStatus.ready ||
            runtimeState.status == EmbeddingRuntimeStatus.installedUnverified,
        filePresent: runtimeState.status != EmbeddingRuntimeStatus.missing,
      );
    }

    if (catalogEntry.type == 'llm') {
      final runtimeResult = await _ref
          .read(llmRuntimeBridgeProvider)
          .ensureModelReady(
            modelId: catalogEntry.id,
            modelPath: result.localPath,
          );
      final runtimeState = mapLlmRuntimeState(
        runtimeResult,
        fallbackPath: result.localPath,
      );
      registryEntry = registryEntry.copyWith(
        enabled:
            runtimeState.status == LlmRuntimeStatus.ready ||
            runtimeState.status == LlmRuntimeStatus.installedUnverified,
        filePresent: runtimeState.status != LlmRuntimeStatus.missing,
      );
    }

    return registryEntry;
  }

  Future<ModelRegistryEntry> _normalizeRegistryEntry(
    ModelRegistryEntry entry,
  ) async {
    final present = await _downloadService.fileExists(entry.localPath);

    var normalized = entry.copyWith(
      filePresent: present,
      enabled: entry.enabled && present,
      integrityStatus: present
          ? entry.integrityStatus
          : ModelIntegrityStatus.unknown,
    );

    if (present &&
        entry.localPath != null &&
        entry.localPath!.trim().isNotEmpty) {
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
