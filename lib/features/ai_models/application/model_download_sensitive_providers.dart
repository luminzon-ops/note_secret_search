part of 'model_download_providers.dart';

final modelRegistryEntriesProvider = FutureProvider<List<ModelRegistryEntry>>((
  ref,
) {
  return guardSensitiveFuture<List<ModelRegistryEntry>>(
    ref,
    lockedValue: const <ModelRegistryEntry>[],
    load: () async {
      final repository = ref.watch(modelRegistryRepositoryProvider);
      final lifecycleStore = ref.watch(modelLifecycleStoreProvider);
      final downloadService = ref.watch(modelDownloadServiceProvider);
      final integrityVerifier = ModelRegistryIntegrityVerifier(
        downloadService: downloadService,
      );
      final downloadRepository = ref.watch(modelDownloadRepositoryProvider);
      final catalogEntries = await ref.watch(
        modelCatalogEntriesProvider.future,
      );
      final supportedCatalogEntries = catalogEntries
          .where((entry) => entry.type != 'multimodal_llm')
          .toList(growable: false);
      final existingEntries = await repository.listInstalledModels();
      final entriesById = <String, ModelRegistryEntry>{
        for (final entry in existingEntries) entry.id: entry,
      };

      for (final catalogEntry in supportedCatalogEntries) {
        if (entriesById.containsKey(catalogEntry.id)) {
          continue;
        }

        ModelDownloadTask? latestTask;
        var latestTaskLoaded = false;
        for (final source in catalogEntry.sources) {
          if (source.checksum.trim().isEmpty) {
            continue;
          }
          final target = await downloadService.inspectDownloadTarget(
            modelId: catalogEntry.id,
            sourceUrl: source.url,
          );
          if (!target.exists || target.existingBytes <= 0) {
            continue;
          }
          if (!latestTaskLoaded) {
            latestTask = await downloadRepository.findLatestTaskByModel(
              catalogEntry.id,
            );
            latestTaskLoaded = true;
          }
          if (latestTask != null) {
            if (latestTask.status != ModelDownloadStatus.completed) {
              break;
            }
            if (latestTask.sourceId != source.id) {
              continue;
            }
          }

          try {
            final verifiedChecksum = await downloadService.verifyChecksum(
              filePath: target.localPath,
              expectedChecksum: source.checksum,
            );
            final now = DateTime.now();
            final adopted = ModelRegistryEntry(
              id: catalogEntry.id,
              type: catalogEntry.type,
              provider: 'builtin_catalog',
              name: catalogEntry.displayName,
              version: null,
              sizeBytes: target.existingBytes,
              quantization: null,
              minRamMb: catalogEntry.minRamMb,
              recommendedTier: catalogEntry.recommendedTier,
              localPath: target.localPath,
              checksum: verifiedChecksum,
              enabled: true,
              installedAt: now,
              filePresent: true,
              integrityStatus: ModelIntegrityStatus.valid,
            );
            await lifecycleStore.commitInstallation(
              registryEntry: adopted,
              completedTasks: <ModelDownloadTask>[
                ModelDownloadTask(
                  id: _adoptedDownloadTaskId(catalogEntry.id, source.id),
                  modelId: catalogEntry.id,
                  sourceId: source.id,
                  status: ModelDownloadStatus.completed,
                  totalBytes: target.existingBytes,
                  downloadedBytes: target.existingBytes,
                  averageSpeed: null,
                  errorMessage: null,
                  resumable: true,
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
            );
            entriesById[adopted.id] = adopted;
            break;
          } catch (_) {
            continue;
          }
        }
      }

      final entries = entriesById.values.toList(growable: false);
      final resolved = <ModelRegistryEntry>[];

      for (final entry in entries) {
        if (entry.type == 'multimodal_llm') {
          resolved.add(entry);
          continue;
        }
        final normalized = await integrityVerifier.verify(entry);
        if (modelRegistryIntegrityChanged(entry, normalized)) {
          await repository.save(normalized);
        }
        resolved.add(normalized);
      }

      return resolved;
    },
  );
});

String _adoptedDownloadTaskId(String modelId, String sourceId) {
  return 'adopted:$modelId:$sourceId';
}

final embeddingRuntimeStatesProvider =
    FutureProvider<Map<String, EmbeddingEngineState>>((ref) {
      return guardSensitiveFuture<Map<String, EmbeddingEngineState>>(
        ref,
        lockedValue: const <String, EmbeddingEngineState>{},
        load: () async {
          final entries = await ref.watch(modelRegistryEntriesProvider.future);
          final embeddingEngine = ref.watch(embeddingEngineProvider);
          final resolved = <String, EmbeddingEngineState>{};

          for (final entry in entries) {
            if (entry.type != 'embedding') {
              continue;
            }

            if (entry.localPath == null || entry.localPath!.trim().isEmpty) {
              resolved[entry.id] = const EmbeddingEngineState(
                ready: false,
                reason: '尚未配置本地 embedding 模型文件。',
                status: EmbeddingRuntimeStatus.notInstalled,
              );
              continue;
            }

            if (!entry.filePresent) {
              resolved[entry.id] = EmbeddingEngineState(
                ready: false,
                reason: '本地模型文件缺失，需要重新下载或修复。',
                status: EmbeddingRuntimeStatus.missing,
                modelPath: entry.localPath,
              );
              continue;
            }

            if (entry.integrityStatus == ModelIntegrityStatus.corrupted) {
              resolved[entry.id] = EmbeddingEngineState(
                ready: false,
                reason: '本地模型文件校验失败，需要重新下载或修复。',
                status: EmbeddingRuntimeStatus.corrupted,
                modelPath: entry.localPath,
              );
              continue;
            }

            resolved[entry.id] = await embeddingEngine.getState(entry);
          }

          return resolved;
        },
      );
    });

final modelDownloadTasksProvider = FutureProvider<List<ModelDownloadTask>>((
  ref,
) {
  return guardSensitiveFuture<List<ModelDownloadTask>>(
    ref,
    lockedValue: const <ModelDownloadTask>[],
    load: () async {
      final repository = ref.watch(modelDownloadRepositoryProvider);
      final downloadService = ref.watch(modelDownloadServiceProvider);
      final catalogEntries = await ref.watch(
        modelCatalogEntriesProvider.future,
      );
      final catalogByModelId = <String, ModelCatalogEntry>{
        for (final entry in catalogEntries) entry.id: entry,
      };
      final tasks = await repository.listTasks();
      final resolved = <ModelDownloadTask>[];

      for (final task in tasks) {
        final catalogEntry = catalogByModelId[task.modelId];
        final source = catalogEntry?.sources
            .where((item) => item.id == task.sourceId)
            .firstOrNull;
        if (catalogEntry == null || source == null) {
          resolved.add(task);
          continue;
        }

        final target = await downloadService.inspectDownloadTarget(
          modelId: task.modelId,
          sourceUrl: source.url,
        );

        var next = task;
        if (task.downloadedBytes != target.existingBytes) {
          next = next.copyWith(downloadedBytes: target.existingBytes);
        }

        if ((task.status == ModelDownloadStatus.queued ||
                task.status == ModelDownloadStatus.downloading) &&
            target.existingBytes > 0) {
          next = next.copyWith(
            status: ModelDownloadStatus.paused,
            downloadedBytes: target.existingBytes,
            updatedAt: DateTime.now(),
          );
        }

        if (next != task) {
          await repository.saveTask(next);
        }
        resolved.add(next);
      }

      return resolved;
    },
  );
});
