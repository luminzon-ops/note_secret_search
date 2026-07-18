import 'dart:async';

import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

enum ModelLifecycleCheckpoint {
  registryWritten,
  tasksWritten,
  relatedDataDeleted,
  registryDeleted,
}

typedef ModelLifecycleCheckpointCallback =
    FutureOr<void> Function(ModelLifecycleCheckpoint checkpoint);

class SqliteModelLifecycleStore implements ModelLifecycleStore {
  SqliteModelLifecycleStore({
    required AppDatabase database,
    ModelLifecycleCheckpointCallback? checkpoint,
  }) : _database = database,
       _checkpoint = checkpoint,
       _registryRepository = SqliteModelRegistryRepository(database: database);

  final AppDatabase _database;
  final ModelLifecycleCheckpointCallback? _checkpoint;
  final SqliteModelRegistryRepository _registryRepository;

  @override
  Future<void> commitInstallation({
    required ModelRegistryEntry registryEntry,
    required List<ModelDownloadTask> completedTasks,
  }) {
    _validateInstallation(registryEntry, completedTasks);
    return _database.transaction((executor) async {
      await _upsertRegistry(executor, registryEntry);
      await _notify(ModelLifecycleCheckpoint.registryWritten);
      for (final task in completedTasks) {
        await _upsertTask(executor, task);
      }
      await _notify(ModelLifecycleCheckpoint.tasksWritten);
    });
  }

  @override
  Future<ModelRegistryEntry?> getDeletionManifest(String modelId) {
    _validateModelId(modelId);
    return _registryRepository.getById(modelId);
  }

  @override
  Future<void> purgeModelData(String modelId) {
    _validateModelId(modelId);
    return _database.transaction((executor) async {
      await executor.delete(
        DatabaseSchema.embeddingChunks,
        where: 'model_id = ?',
        whereArgs: <Object>[modelId],
      );
      await executor.delete(
        DatabaseSchema.downloadTasks,
        where: 'model_id = ?',
        whereArgs: <Object>[modelId],
      );
      await _notify(ModelLifecycleCheckpoint.relatedDataDeleted);
      await executor.delete(
        DatabaseSchema.modelRegistry,
        where: 'id = ?',
        whereArgs: <Object>[modelId],
      );
      await _notify(ModelLifecycleCheckpoint.registryDeleted);
    });
  }

  Future<void> _notify(ModelLifecycleCheckpoint checkpoint) {
    final callback = _checkpoint;
    if (callback == null) {
      return Future<void>.value();
    }
    return Future<void>.sync(() => callback(checkpoint));
  }
}

void _validateInstallation(
  ModelRegistryEntry registryEntry,
  List<ModelDownloadTask> completedTasks,
) {
  _validateModelId(registryEntry.id);
  if (completedTasks.isEmpty) {
    throw ArgumentError.value(
      completedTasks,
      'completedTasks',
      'At least one completed task is required.',
    );
  }
  for (final task in completedTasks) {
    if (task.modelId != registryEntry.id ||
        task.status != ModelDownloadStatus.completed) {
      throw ArgumentError.value(
        completedTasks,
        'completedTasks',
        'Every task must be completed and belong to the registry model.',
      );
    }
  }
}

void _validateModelId(String modelId) {
  if (modelId.trim().isEmpty) {
    throw ArgumentError.value(modelId, 'modelId', 'Model id is required.');
  }
}

Future<void> _upsertRegistry(
  DatabaseExecutor executor,
  ModelRegistryEntry entry,
) async {
  await executor.rawInsert(
    '''
    INSERT INTO ${DatabaseSchema.modelRegistry} (
      id,
      type,
      provider,
      name,
      version,
      size_bytes,
      quantization,
      min_ram_mb,
      recommended_tier,
      local_path,
      artifact_paths_json,
      checksum,
      integrity_status,
      enabled,
      installed_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      type = excluded.type,
      provider = excluded.provider,
      name = excluded.name,
      version = excluded.version,
      size_bytes = excluded.size_bytes,
      quantization = excluded.quantization,
      min_ram_mb = excluded.min_ram_mb,
      recommended_tier = excluded.recommended_tier,
      local_path = excluded.local_path,
      artifact_paths_json = excluded.artifact_paths_json,
      checksum = excluded.checksum,
      integrity_status = excluded.integrity_status,
      enabled = excluded.enabled,
      installed_at = excluded.installed_at
    ''',
    <Object?>[
      entry.id,
      entry.type,
      entry.provider,
      entry.name,
      entry.version,
      entry.sizeBytes,
      entry.quantization,
      entry.minRamMb,
      entry.recommendedTier,
      entry.localPath,
      encodeModelArtifactPathsForSqlite(entry.artifacts),
      entry.checksum,
      entry.integrityStatus.name,
      entry.enabled ? 1 : 0,
      entry.installedAt?.millisecondsSinceEpoch,
    ],
  );
}

Future<void> _upsertTask(
  DatabaseExecutor executor,
  ModelDownloadTask task,
) async {
  await executor.rawInsert(
    '''
    INSERT INTO ${DatabaseSchema.downloadTasks} (
      id,
      model_id,
      source_id,
      status,
      total_bytes,
      downloaded_bytes,
      average_speed,
      error_message,
      resumable,
      created_at,
      updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      model_id = excluded.model_id,
      source_id = excluded.source_id,
      status = excluded.status,
      total_bytes = excluded.total_bytes,
      downloaded_bytes = excluded.downloaded_bytes,
      average_speed = excluded.average_speed,
      error_message = excluded.error_message,
      resumable = excluded.resumable,
      created_at = excluded.created_at,
      updated_at = excluded.updated_at
    ''',
    <Object?>[
      task.id,
      task.modelId,
      task.sourceId,
      task.status.name,
      task.totalBytes,
      task.downloadedBytes,
      task.averageSpeed,
      task.errorMessage,
      task.resumable ? 1 : 0,
      task.createdAt.millisecondsSinceEpoch,
      task.updatedAt.millisecondsSinceEpoch,
    ],
  );
}
