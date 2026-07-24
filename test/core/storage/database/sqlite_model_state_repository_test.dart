import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_model_state_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SqliteModelStateRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    repository = SqliteModelStateRepository(database: database);
  });

  tearDown(() => database.close());

  test(
    'round trips catalog state, registry artifact, download checkpoint, and journal',
    () async {
      await database.run((db) async {
        await db.insert(DatabaseSchema.modelRegistry, <String, Object?>{
          'id': 'model-1',
          'type': 'embedding',
          'provider': 'builtin',
          'name': 'Model 1',
          'enabled': 0,
          'integrity_status': 'unknown',
        });
      });

      await repository.saveCatalogState(
        ModelCatalogStateRecord(
          id: 'active',
          acceptedVersion: 12,
          acceptedDigest: 'a' * 64,
          acceptedKeyId: 'key-1',
          acceptedSchemaVersion: 1,
          minimumAcceptedVersion: 10,
          updatedAt: 100,
        ),
      );
      await repository.saveRegistryArtifact(
        ModelRegistryArtifactRecord(
          modelId: 'model-1',
          releaseId: 'release-1',
          artifactId: 'artifact-model',
          role: 'model',
          required: true,
          relativePath: 'model/model.bin',
          expectedSizeBytes: 1024,
          expectedSha256: 'sha256:${'b' * 64}',
          verifiedSizeBytes: 1024,
          verifiedSha256: 'sha256:${'b' * 64}',
          sourceId: 'mirror-a',
          state: 'verified',
          verifiedAt: 101,
        ),
      );
      await repository.saveDownloadCheckpoint(
        ModelDownloadCheckpointRecord(
          taskId: 'task-1',
          modelId: 'model-1',
          sourceId: 'mirror-a',
          status: 'downloading',
          operationId: 'operation-1',
          attemptGeneration: 2,
          releaseId: 'release-1',
          artifactId: 'artifact-model',
          sourceUrl: 'https://example.test/model.bin',
          stagingPath: 'models/model-1/.staging/operation-1/model.bin.part',
          expectedSha256: 'sha256:${'b' * 64}',
          expectedSizeBytes: 1024,
          etag: '"etag-1"',
          lastModified: 'Wed, 01 Jan 2025 00:00:00 GMT',
          checkpoint: 'downloading',
          retryReason: null,
          receivedBytes: 512,
          createdAt: 102,
          updatedAt: 103,
        ),
      );
      await repository.saveInstallJournal(
        const ModelInstallJournalRecord(
          operationId: 'operation-1',
          modelId: 'model-1',
          releaseId: 'release-1',
          attemptGeneration: 2,
          operationType: 'install',
          phase: 'staged',
          oldRevision: 'revision-1',
          newRevision: 'revision-2',
          stagingRoot: 'models/model-1/.staging/operation-1',
          targetRoot: 'models/model-1/revisions/revision-2',
          errorCode: null,
          createdAt: 104,
          updatedAt: 105,
          completedAt: null,
        ),
      );

      final catalog = await repository.loadCatalogState();
      expect(catalog?.acceptedVersion, 12);
      expect(
        (await repository.listRegistryArtifacts('model-1')).single.artifactId,
        'artifact-model',
      );
      final checkpoint = await repository.loadDownloadCheckpoint('task-1');
      expect(checkpoint?.receivedBytes, 512);
      expect(checkpoint?.etag, '"etag-1"');
      final journal = await repository.loadInstallJournal('operation-1');
      expect(journal?.phase, 'staged');
      expect(await repository.listOpenInstallJournals(), hasLength(1));
    },
  );

  test('re-saving a checkpoint and journal is idempotent', () async {
    final checkpoint = ModelDownloadCheckpointRecord(
      taskId: 'task-2',
      modelId: 'model-2',
      sourceId: 'mirror-b',
      status: 'queued',
      operationId: 'operation-2',
      attemptGeneration: 1,
      releaseId: 'release-2',
      artifactId: 'artifact-2',
      sourceUrl: 'https://example.test/other.bin',
      stagingPath: 'models/model-2/.staging/operation-2/other.part',
      expectedSha256: 'sha256:${'c' * 64}',
      expectedSizeBytes: 2,
      etag: null,
      lastModified: null,
      checkpoint: 'queued',
      retryReason: null,
      receivedBytes: 0,
      createdAt: 200,
      updatedAt: 200,
    );
    await repository.saveDownloadCheckpoint(checkpoint);
    await repository.saveDownloadCheckpoint(
      checkpoint.copyWith(
        checkpoint: 'paused',
        receivedBytes: 1,
        updatedAt: 201,
      ),
    );

    final saved = await repository.loadDownloadCheckpoint('task-2');
    expect(saved?.checkpoint, 'paused');
    expect(saved?.receivedBytes, 1);
    expect(
      await database.run(
        (db) => db.rawQuery(
          'SELECT COUNT(*) AS count FROM download_tasks WHERE id = ?',
          <Object>['task-2'],
        ),
      ),
      const <Map<String, Object?>>[
        <String, Object?>{'count': 1},
      ],
    );
  });

  test(
    'catalog acceptance is monotonic and rejects digest conflicts',
    () async {
      await repository.saveCatalogState(
        ModelCatalogStateRecord(
          id: 'active',
          acceptedVersion: 12,
          acceptedDigest: 'a' * 64,
          acceptedKeyId: 'key-1',
          acceptedSchemaVersion: 1,
          minimumAcceptedVersion: 10,
          updatedAt: 100,
        ),
      );

      await expectLater(
        repository.saveCatalogState(
          ModelCatalogStateRecord(
            id: 'active',
            acceptedVersion: 11,
            acceptedDigest: 'a' * 64,
            acceptedKeyId: 'key-1',
            acceptedSchemaVersion: 1,
            minimumAcceptedVersion: 10,
            updatedAt: 101,
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        repository.saveCatalogState(
          ModelCatalogStateRecord(
            id: 'active',
            acceptedVersion: 12,
            acceptedDigest: 'b' * 64,
            acceptedKeyId: 'key-1',
            acceptedSchemaVersion: 1,
            minimumAcceptedVersion: 10,
            updatedAt: 102,
          ),
        ),
        throwsStateError,
      );

      await repository.saveCatalogState(
        ModelCatalogStateRecord(
          id: 'active',
          acceptedVersion: 13,
          acceptedDigest: 'c' * 64,
          acceptedKeyId: 'key-2',
          acceptedSchemaVersion: 1,
          minimumAcceptedVersion: 1,
          updatedAt: 103,
        ),
      );
      final accepted = await repository.loadCatalogState();
      expect(accepted?.acceptedVersion, 13);
      expect(accepted?.minimumAcceptedVersion, 10);
    },
  );

  test('state repository rejects weak digests and unsafe paths', () async {
    expect(
      () => repository.saveCatalogState(
        const ModelCatalogStateRecord(
          id: 'active',
          acceptedVersion: 1,
          acceptedDigest: 'weak',
          acceptedKeyId: 'key-1',
          acceptedSchemaVersion: 1,
          minimumAcceptedVersion: 1,
          updatedAt: 1,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => repository.saveRegistryArtifact(
        ModelRegistryArtifactRecord(
          modelId: 'model-1',
          releaseId: 'release-1',
          artifactId: 'artifact-model',
          role: 'model',
          required: true,
          relativePath: '../model.bin',
          expectedSizeBytes: 1,
          expectedSha256: 'sha256:${'d' * 64}',
          state: 'unknown',
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => repository.saveDownloadCheckpoint(
        const ModelDownloadCheckpointRecord(
          taskId: 'task-weak',
          modelId: 'model-1',
          sourceId: 'source-1',
          status: 'queued',
          attemptGeneration: 0,
          expectedSha256: 'sha256:ABC',
          checkpoint: 'queued',
          receivedBytes: 0,
          createdAt: 1,
          updatedAt: 1,
        ),
      ),
      throwsArgumentError,
    );
  });
}
