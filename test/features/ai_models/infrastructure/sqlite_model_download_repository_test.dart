import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_download_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SqliteModelDownloadRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    repository = SqliteModelDownloadRepository(database: database);
    await database.run((db) {
      return db.insert(DatabaseSchema.modelRegistry, <String, Object?>{
        'id': 'model-1',
        'type': 'embedding',
        'provider': 'builtin',
        'name': 'Model 1',
        'enabled': 0,
        'integrity_status': 'unknown',
      });
    });
  });

  tearDown(() => database.close());

  test(
    'round trips artifact identity validators and checkpoint phase',
    () async {
      await repository.saveTask(
        _task(
          generation: 2,
          receivedBytes: 512,
          phase: ModelDownloadPhase.downloading,
          etag: '"v1"',
        ),
      );

      final saved = await repository.findLatestTaskByModelAndSource(
        'model-1',
        'source-a',
      );
      expect(saved?.operationId, 'operation-1');
      expect(saved?.releaseId, 'release-1');
      expect(saved?.artifactId, 'artifact-1');
      expect(saved?.attemptGeneration, 2);
      expect(saved?.effectiveReceivedBytes, 512);
      expect(saved?.etag, '"v1"');
      expect(saved?.phase, ModelDownloadPhase.downloading);
    },
  );

  test('late generations and regressing progress are discarded', () async {
    await repository.saveTask(
      _task(
        generation: 2,
        receivedBytes: 512,
        phase: ModelDownloadPhase.downloading,
      ),
    );
    await repository.saveTask(
      _task(
        generation: 1,
        receivedBytes: 900,
        phase: ModelDownloadPhase.downloading,
        updatedAt: DateTime(2026, 7, 24, 10, 1),
      ),
    );
    await repository.saveTask(
      _task(
        generation: 2,
        receivedBytes: 256,
        phase: ModelDownloadPhase.downloading,
        updatedAt: DateTime(2026, 7, 24, 10, 2),
      ),
    );

    final saved = await repository.findLatestTaskByModelAndSource(
      'model-1',
      'source-a',
    );
    expect(saved?.attemptGeneration, 2);
    expect(saved?.effectiveReceivedBytes, 512);
  });

  test('same generation identity drift is discarded', () async {
    await repository.saveTask(
      _task(
        generation: 3,
        receivedBytes: 100,
        phase: ModelDownloadPhase.downloading,
      ),
    );
    await repository.saveTask(
      _task(
        generation: 3,
        receivedBytes: 200,
        phase: ModelDownloadPhase.downloading,
        sourceId: 'source-b',
        sourceUrl: 'https://example.test/mirror-b.bin',
        updatedAt: DateTime(2026, 7, 24, 10, 1),
      ),
    );

    final saved = await repository.findLatestTaskByModel('model-1');
    expect(saved?.sourceId, 'source-a');
    expect(saved?.sourceUrl, 'https://example.test/model.bin');
    expect(saved?.effectiveReceivedBytes, 100);
  });

  test(
    'retryable artifact task switches mirror only after a full reset',
    () async {
      await repository.saveTask(
        _task(
          generation: 3,
          receivedBytes: 512,
          phase: ModelDownloadPhase.retryableFailed,
          status: ModelDownloadStatus.failed,
          etag: '"mirror-a"',
        ),
      );
      await repository.saveTask(
        _task(
          generation: 3,
          receivedBytes: 0,
          phase: ModelDownloadPhase.downloading,
          sourceId: 'source-b',
          sourceUrl: 'https://example.test/mirror-b.bin',
          updatedAt: DateTime(2026, 7, 24, 10, 1),
        ),
      );

      final saved = await repository.findLatestTaskByModel('model-1');
      expect(saved?.sourceId, 'source-b');
      expect(saved?.sourceUrl, 'https://example.test/mirror-b.bin');
      expect(saved?.effectiveReceivedBytes, 0);
      expect(saved?.etag, isNull);
      expect(
        await database.run(
          (db) => db.rawQuery(
            'SELECT COUNT(*) AS count FROM download_tasks '
            'WHERE operation_id = ? AND artifact_id = ?',
            <Object>['operation-1', 'artifact-1'],
          ),
        ),
        const <Map<String, Object?>>[
          <String, Object?>{'count': 1},
        ],
      );
    },
  );

  test('terminal checkpoint only reopens with a newer generation', () async {
    await repository.saveTask(
      _task(
        generation: 4,
        receivedBytes: 1024,
        phase: ModelDownloadPhase.completed,
        status: ModelDownloadStatus.completed,
      ),
    );
    await repository.saveTask(
      _task(
        generation: 4,
        receivedBytes: 1024,
        phase: ModelDownloadPhase.downloading,
        updatedAt: DateTime(2026, 7, 24, 10, 1),
      ),
    );

    var saved = await repository.findLatestTaskByModel('model-1');
    expect(saved?.phase, ModelDownloadPhase.completed);
    expect(saved?.status, ModelDownloadStatus.completed);

    await repository.saveTask(
      _task(
        generation: 5,
        receivedBytes: 0,
        phase: ModelDownloadPhase.queued,
        updatedAt: DateTime(2026, 7, 24, 10, 2),
      ),
    );
    saved = await repository.findLatestTaskByModel('model-1');
    expect(saved?.attemptGeneration, 5);
    expect(saved?.phase, ModelDownloadPhase.queued);
  });
}

ModelDownloadTask _task({
  required int generation,
  required int receivedBytes,
  required ModelDownloadPhase phase,
  ModelDownloadStatus status = ModelDownloadStatus.downloading,
  String sourceId = 'source-a',
  String sourceUrl = 'https://example.test/model.bin',
  String? etag,
  DateTime? updatedAt,
}) {
  return ModelDownloadTask(
    id: 'task-1',
    modelId: 'model-1',
    sourceId: sourceId,
    status: status,
    totalBytes: 1024,
    downloadedBytes: receivedBytes,
    averageSpeed: 128,
    errorMessage: null,
    resumable: true,
    createdAt: DateTime(2026, 7, 24, 10),
    updatedAt: updatedAt ?? DateTime(2026, 7, 24, 10),
    operationId: 'operation-1',
    attemptGeneration: generation,
    releaseId: 'release-1',
    artifactId: 'artifact-1',
    sourceUrl: sourceUrl,
    stagingPath: 'models/model-1/.staging/operation-1/artifact-1.part',
    expectedChecksum: 'sha256:${'a' * 64}',
    expectedSizeBytes: 1024,
    etag: etag,
    phase: phase,
    receivedBytes: receivedBytes,
  );
}
