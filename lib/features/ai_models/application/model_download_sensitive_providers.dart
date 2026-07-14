part of 'model_download_providers.dart';

final modelRegistryEntriesProvider = FutureProvider<List<ModelRegistryEntry>>((
  ref,
) {
  return guardSensitiveFuture<List<ModelRegistryEntry>>(
    ref,
    lockedValue: const <ModelRegistryEntry>[],
    load: () async {
      final repository = ref.watch(modelRegistryRepositoryProvider);
      final downloadService = ref.watch(modelDownloadServiceProvider);
      final catalogEntries = await ref.watch(
        modelCatalogEntriesProvider.future,
      );
      final existingEntries = await repository.listInstalledModels();
      final entriesById = <String, ModelRegistryEntry>{
        for (final entry in existingEntries) entry.id: entry,
      };

      for (final catalogEntry in catalogEntries) {
        if (entriesById.containsKey(catalogEntry.id)) {
          continue;
        }

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

          try {
            final verifiedChecksum = await downloadService.verifyChecksum(
              filePath: target.localPath,
              expectedChecksum: source.checksum,
            );
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
              installedAt: DateTime.now(),
              filePresent: true,
              integrityStatus: ModelIntegrityStatus.valid,
            );
            await repository.save(adopted);
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
        final present = await downloadService.fileExists(entry.localPath);
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
              await downloadService.verifyChecksum(
                filePath: entry.localPath!,
                expectedChecksum: expectedChecksum,
              );
              normalized = normalized.copyWith(
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

        if (normalized.enabled != entry.enabled ||
            normalized.filePresent != entry.filePresent) {
          await repository.save(normalized);
        } else if (normalized.integrityStatus != entry.integrityStatus) {
          await repository.save(normalized);
        }
        resolved.add(normalized);
      }

      return resolved;
    },
  );
});

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
