import 'dart:async';

import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_download_repository.dart';
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
    void Function()? beforeMutation,
  }) : _database = database,
       _checkpoint = checkpoint,
       _beforeMutation = beforeMutation,
       _registryRepository = SqliteModelRegistryRepository(database: database);

  final AppDatabase _database;
  final ModelLifecycleCheckpointCallback? _checkpoint;
  final void Function()? _beforeMutation;
  final SqliteModelRegistryRepository _registryRepository;

  @override
  Future<void> commitInstallation({
    required ModelRegistryEntry registryEntry,
    required List<ModelDownloadTask> completedTasks,
  }) {
    _validateInstallation(registryEntry, completedTasks);
    _beforeMutation?.call();
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
    _beforeMutation?.call();
    return _database.transaction((executor) async {
      await executor.delete(
        DatabaseSchema.embeddingIndexSets,
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
  await writeModelRegistryEntry(executor, entry);
}

Future<void> _upsertTask(
  DatabaseExecutor executor,
  ModelDownloadTask task,
) async {
  await upsertModelDownloadTask(executor, task);
}
