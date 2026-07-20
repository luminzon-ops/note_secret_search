import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_lifecycle_store.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test('installation is atomic and idempotent', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    final entry = _registryEntry();
    final tasks = <ModelDownloadTask>[
      _completedTask(id: 'task-1', sourceId: 'source-1'),
      _completedTask(id: 'task-2', sourceId: 'source-2'),
    ];
    final failingStore = SqliteModelLifecycleStore(
      database: database,
      checkpoint: (checkpoint) {
        if (checkpoint == ModelLifecycleCheckpoint.registryWritten) {
          throw StateError('injected_install_failure');
        }
      },
    );

    await expectLater(
      failingStore.commitInstallation(
        registryEntry: entry,
        completedTasks: tasks,
      ),
      throwsStateError,
    );

    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.modelRegistry),
      ),
      isEmpty,
    );
    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.downloadTasks),
      ),
      isEmpty,
    );

    final store = SqliteModelLifecycleStore(database: database);
    await store.commitInstallation(registryEntry: entry, completedTasks: tasks);
    await store.commitInstallation(registryEntry: entry, completedTasks: tasks);

    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.modelRegistry),
      ),
      hasLength(1),
    );
    final taskRows = await database.run(
      (executor) =>
          executor.query(DatabaseSchema.downloadTasks, orderBy: 'id ASC'),
    );
    expect(taskRows, hasLength(2));
    expect(
      taskRows.map((row) => row['status']),
      everyElement(ModelDownloadStatus.completed.name),
    );
  });

  test('purge rolls back related cleanup and can be retried', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    final store = SqliteModelLifecycleStore(database: database);
    await store.commitInstallation(
      registryEntry: _registryEntry(),
      completedTasks: <ModelDownloadTask>[
        _completedTask(id: 'task-1', sourceId: 'source-1'),
      ],
    );
    await database.run((executor) async {
      await executor.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': 'secret-1',
        'vault_id': 'default',
        'title': 'Source',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await executor.insert(
        DatabaseSchema.embeddingIndexSets,
        <String, Object?>{
          'id': 'embedding-set-1',
          'source_type': 'secret',
          'source_id': 'secret-1',
          'vault_id': 'default',
          'model_id': 'model-1',
          'model_revision_hash': 'a' * 64,
          'source_updated_at': 1,
          'source_fingerprint': Uint8List(32),
          'fingerprint_key_id': 'test-key',
          'fingerprint_version': 1,
          'index_config_version': 1,
          'index_config_epoch': 1,
          'index_config_hash': 'b' * 64,
          'chunk_schema_version': 1,
          'vector_format_version': 1,
          'vector_dimension': 1,
          'chunk_count': 1,
          'created_at': 1,
        },
      );
      await executor.insert(DatabaseSchema.embeddingChunks, <String, Object?>{
        'id': 'embedding-chunk-1',
        'index_set_id': 'embedding-set-1',
        'source_field': 'secret.title',
        'field_chunk_index': 0,
        'chunk_fingerprint': Uint8List(32),
        'vector_blob': Uint8List(4),
        'token_count': 1,
        'created_at': 1,
      });
    });
    final failingStore = SqliteModelLifecycleStore(
      database: database,
      checkpoint: (checkpoint) {
        if (checkpoint == ModelLifecycleCheckpoint.relatedDataDeleted) {
          throw StateError('injected_purge_failure');
        }
      },
    );

    await expectLater(failingStore.purgeModelData('model-1'), throwsStateError);

    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.modelRegistry),
      ),
      hasLength(1),
    );
    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.downloadTasks),
      ),
      hasLength(1),
    );
    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.embeddingIndexSets),
      ),
      hasLength(1),
    );
    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.embeddingChunks),
      ),
      hasLength(1),
    );

    await store.purgeModelData('model-1');
    await store.purgeModelData('model-1');

    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.modelRegistry),
      ),
      isEmpty,
    );
    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.downloadTasks),
      ),
      isEmpty,
    );
    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.embeddingIndexSets),
      ),
      isEmpty,
    );
    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.embeddingChunks),
      ),
      isEmpty,
    );
  });
}

ModelRegistryEntry _registryEntry() {
  return ModelRegistryEntry(
    id: 'model-1',
    type: 'embedding',
    provider: 'builtin_catalog',
    name: 'Model',
    version: null,
    sizeBytes: 30,
    quantization: null,
    minRamMb: 512,
    recommendedTier: 'mvp',
    localPath: '/models/model-1/model.onnx',
    checksum: 'sha256:model',
    enabled: false,
    installedAt: DateTime(2026, 7, 18),
    filePresent: true,
    integrityStatus: ModelIntegrityStatus.valid,
  );
}

ModelDownloadTask _completedTask({
  required String id,
  required String sourceId,
}) {
  return ModelDownloadTask(
    id: id,
    modelId: 'model-1',
    sourceId: sourceId,
    status: ModelDownloadStatus.completed,
    totalBytes: 15,
    downloadedBytes: 15,
    averageSpeed: null,
    errorMessage: null,
    resumable: true,
    createdAt: DateTime(2026, 7, 18, 10),
    updatedAt: DateTime(2026, 7, 18, 11),
  );
}
