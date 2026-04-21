import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:uuid/uuid.dart';

final modelDownloadRepositoryProvider = Provider<ModelDownloadRepository>((ref) {
  return SqliteModelDownloadRepository(database: ref.watch(appDatabaseProvider));
});

final modelRegistryRepositoryProvider = Provider<ModelRegistryRepository>((ref) {
  return SqliteModelRegistryRepository(database: ref.watch(appDatabaseProvider));
});

final modelRegistryEntriesProvider = FutureProvider<List<ModelRegistryEntry>>((ref) async {
  final repository = ref.watch(modelRegistryRepositoryProvider);
  final downloadService = ref.watch(modelDownloadServiceProvider);
  final entries = await repository.listInstalledModels();
  final resolved = <ModelRegistryEntry>[];

  for (final entry in entries) {
    final present = await downloadService.fileExists(entry.localPath);
    final normalized = entry.copyWith(filePresent: present, enabled: entry.enabled && present);
    if (normalized.enabled != entry.enabled || normalized.filePresent != entry.filePresent) {
      await repository.save(normalized);
    }
    resolved.add(normalized);
  }

  return resolved;
});

final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  return ModelDownloadService(
    dio: Dio(),
    logger: ref.watch(loggerProvider),
  );
});

final modelDownloadTasksProvider = FutureProvider<List<ModelDownloadTask>>((ref) async {
  return ref.watch(modelDownloadRepositoryProvider).listTasks();
});

final modelDownloadControllerProvider = Provider<ModelDownloadController>((ref) {
  return ModelDownloadController(
    ref: ref,
    repository: ref.watch(modelDownloadRepositoryProvider),
    registryRepository: ref.watch(modelRegistryRepositoryProvider),
    downloadService: ref.watch(modelDownloadServiceProvider),
    logger: ref.watch(loggerProvider),
  );
});

class ModelDownloadController {
  ModelDownloadController({
    required Ref ref,
    required ModelDownloadRepository repository,
    required ModelRegistryRepository registryRepository,
    required ModelDownloadService downloadService,
    required AppLogger logger,
  })
      : _ref = ref,
        _repository = repository,
        _registryRepository = registryRepository,
        _downloadService = downloadService,
        _logger = logger;

  final Ref _ref;
  final ModelDownloadRepository _repository;
  final ModelRegistryRepository _registryRepository;
  final ModelDownloadService _downloadService;
  final AppLogger _logger;
  static const _uuid = Uuid();

  Future<void> enqueueDownload({
    required String modelId,
    required String sourceId,
    required int? totalBytes,
  }) async {
    final existing = await _repository.findLatestTaskByModel(modelId);
    final now = DateTime.now();

    if (existing != null &&
        (existing.status == ModelDownloadStatus.queued ||
            existing.status == ModelDownloadStatus.downloading ||
            existing.status == ModelDownloadStatus.paused)) {
      final next = existing.copyWith(
        status: ModelDownloadStatus.queued,
        totalBytes: totalBytes ?? existing.totalBytes,
        errorMessage: null,
        clearErrorMessage: true,
        updatedAt: now,
      );
      await _repository.saveTask(next);
      _ref.invalidate(modelDownloadTasksProvider);
      return;
    }

    final task = ModelDownloadTask(
      id: _uuid.v4(),
      modelId: modelId,
      sourceId: sourceId,
      status: ModelDownloadStatus.queued,
      totalBytes: totalBytes,
      downloadedBytes: 0,
      averageSpeed: null,
      errorMessage: null,
      resumable: true,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.saveTask(task);
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> markDownloading(String modelId) async {
    final task = await _repository.findLatestTaskByModel(modelId);
    if (task == null) {
      return;
    }

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.downloading,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> startDownload({
    required ModelCatalogEntry entry,
    required ModelSourceEntry source,
  }) async {
    final existingRegistry = await _registryRepository.getById(entry.id);
    if (existingRegistry != null && await _downloadService.fileExists(existingRegistry.localPath)) {
      _ref.invalidate(modelRegistryEntriesProvider);
      return;
    }

    await enqueueDownload(
      modelId: entry.id,
      sourceId: source.id,
      totalBytes: entry.sizeBytes,
    );

    final task = await _repository.findLatestTaskByModel(entry.id);
    if (task == null) {
      return;
    }

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.downloading,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);

    try {
      final result = await _downloadService.download(
        taskId: task.id,
        modelId: entry.id,
        sourceUrl: source.url,
        onProgress: (progress) async {
          final current = await _repository.findLatestTaskByModel(entry.id);
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

      await _repository.saveTask(
        task.copyWith(
          status: ModelDownloadStatus.completed,
          downloadedBytes: result.totalBytes,
          totalBytes: result.totalBytes,
          updatedAt: DateTime.now(),
          errorMessage: null,
          clearErrorMessage: true,
        ),
      );

      await _registryRepository.save(
        ModelRegistryEntry(
          id: entry.id,
          type: entry.type,
          provider: 'builtin_catalog',
          name: entry.displayName,
          version: null,
          sizeBytes: result.totalBytes,
          quantization: null,
          minRamMb: entry.minRamMb,
          recommendedTier: entry.recommendedTier,
          localPath: result.localPath,
          checksum: null,
          enabled: true,
          installedAt: DateTime.now(),
          filePresent: true,
        ),
      );

      _ref.invalidate(modelDownloadTasksProvider);
      _ref.invalidate(modelRegistryEntriesProvider);
    } catch (error, stackTrace) {
      _logger.error('Model download failed for ${entry.id}', error, stackTrace);
      await markFailed(entry.id, error.toString());
    }
  }

  Future<void> pause(String modelId) async {
    final task = await _repository.findLatestTaskByModel(modelId);
    if (task == null) {
      return;
    }

    _downloadService.cancel(task.id);

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.paused,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> deleteInstalledModel(String modelId) async {
    final existing = await _registryRepository.getById(modelId);
    if (existing == null) {
      return;
    }

    await _downloadService.deleteLocalFile(existing.localPath);
    await _registryRepository.deleteById(modelId);
    await markFailed(modelId, '本地模型文件已删除，可重新下载。');
    _ref.invalidate(modelRegistryEntriesProvider);
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<bool> isInstalled(String modelId) async {
    final existing = await _registryRepository.getById(modelId);
    if (existing == null) {
      return false;
    }
    return _downloadService.fileExists(existing.localPath);
  }

  Future<void> markFailed(String modelId, String message) async {
    final task = await _repository.findLatestTaskByModel(modelId);
    if (task == null) {
      return;
    }

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.failed,
        errorMessage: message,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }

  Future<void> markCompleted(String modelId) async {
    final task = await _repository.findLatestTaskByModel(modelId);
    if (task == null) {
      return;
    }

    await _repository.saveTask(
      task.copyWith(
        status: ModelDownloadStatus.completed,
        downloadedBytes: task.totalBytes ?? task.downloadedBytes,
        updatedAt: DateTime.now(),
      ),
    );
    _ref.invalidate(modelDownloadTasksProvider);
  }
}
