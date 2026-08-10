import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

class SqliteModelDownloadRepository implements ModelDownloadRepository {
  SqliteModelDownloadRepository({required AppDatabase database})
    : _database = database;

  final AppDatabase _database;

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.downloadTasks,
        where: 'model_id = ?',
        whereArgs: <Object>[modelId],
        orderBy: 'updated_at DESC',
        limit: 1,
      );

      if (rows.isEmpty) {
        return null;
      }

      return _mapTask(rows.first);
    });
  }

  @override
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(
    String modelId,
    String sourceId,
  ) {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.downloadTasks,
        where: 'model_id = ? AND source_id = ?',
        whereArgs: <Object>[modelId, sourceId],
        orderBy: 'updated_at DESC',
        limit: 1,
      );

      if (rows.isEmpty) {
        return null;
      }

      return _mapTask(rows.first);
    });
  }

  @override
  Future<List<ModelDownloadTask>> listTasks() {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.downloadTasks,
        orderBy: 'updated_at DESC',
      );

      return rows.map(_mapTask).toList(growable: false);
    });
  }

  @override
  Future<void> saveTask(ModelDownloadTask task) {
    return _database.run((db) => upsertModelDownloadTask(db, task));
  }

  ModelDownloadTask _mapTask(Map<String, Object?> row) {
    return ModelDownloadTask(
      id: row['id']! as String,
      modelId: row['model_id']! as String,
      sourceId: row['source_id']! as String,
      status: _parseStatus(row['status']! as String),
      totalBytes: row['total_bytes'] as int?,
      downloadedBytes: row['downloaded_bytes'] as int? ?? 0,
      averageSpeed: row['average_speed'] as double?,
      errorMessage: row['error_message'] as String?,
      resumable: (row['resumable'] as int? ?? 1) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      operationId: row['operation_id'] as String?,
      attemptGeneration: row['attempt_generation'] as int? ?? 0,
      releaseId: row['release_id'] as String?,
      artifactId: row['artifact_id'] as String?,
      sourceUrl: row['source_url'] as String?,
      stagingPath: row['staging_path'] as String?,
      expectedChecksum: row['expected_sha256'] as String?,
      expectedSizeBytes: row['expected_size_bytes'] as int?,
      etag: row['etag'] as String?,
      lastModified: row['last_modified'] as String?,
      phase: _parsePhase(row['checkpoint'] as String?),
      retryReason: row['retry_reason'] as String?,
      receivedBytes:
          row['received_bytes'] as int? ?? row['downloaded_bytes'] as int? ?? 0,
    );
  }

  ModelDownloadStatus _parseStatus(String raw) {
    return ModelDownloadStatus.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ModelDownloadStatus.idle,
    );
  }

  ModelDownloadPhase _parsePhase(String? raw) {
    if (raw == null) {
      return ModelDownloadPhase.legacy;
    }
    return switch (raw) {
      'runtime_validating' => ModelDownloadPhase.runtimeValidating,
      'releasing_sessions' => ModelDownloadPhase.releasingSessions,
      'retryable_failed' => ModelDownloadPhase.retryableFailed,
      _ => ModelDownloadPhase.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => ModelDownloadPhase.legacy,
      ),
    };
  }
}

Future<void> upsertModelDownloadTask(
  DatabaseExecutor db,
  ModelDownloadTask task,
) async {
  await db.rawInsert(
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
          updated_at,
          operation_id,
          attempt_generation,
          release_id,
          artifact_id,
          source_url,
          staging_path,
          expected_sha256,
          expected_size_bytes,
          checkpoint,
          retry_reason,
          received_bytes,
          etag,
          last_modified
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          updated_at = excluded.updated_at,
          operation_id = excluded.operation_id,
          attempt_generation = excluded.attempt_generation,
          release_id = excluded.release_id,
          artifact_id = excluded.artifact_id,
          source_url = excluded.source_url,
          staging_path = excluded.staging_path,
          expected_sha256 = excluded.expected_sha256,
          expected_size_bytes = excluded.expected_size_bytes,
          checkpoint = excluded.checkpoint,
          retry_reason = excluded.retry_reason,
          received_bytes = excluded.received_bytes,
          etag = excluded.etag,
          last_modified = excluded.last_modified
        WHERE
          excluded.attempt_generation > download_tasks.attempt_generation
          OR (
            excluded.attempt_generation = download_tasks.attempt_generation
            AND excluded.model_id = download_tasks.model_id
            AND excluded.operation_id IS download_tasks.operation_id
            AND excluded.release_id IS download_tasks.release_id
            AND excluded.artifact_id IS download_tasks.artifact_id
            AND excluded.staging_path IS download_tasks.staging_path
            AND excluded.expected_sha256 IS download_tasks.expected_sha256
            AND excluded.expected_size_bytes IS download_tasks.expected_size_bytes
            AND excluded.updated_at >= download_tasks.updated_at
            AND (
              (
                excluded.source_id = download_tasks.source_id
                AND excluded.source_url IS download_tasks.source_url
                AND (
                  download_tasks.checkpoint = 'legacy'
                  OR excluded.received_bytes >= download_tasks.received_bytes
                )
              )
              OR (
                download_tasks.checkpoint = 'retryable_failed'
                AND excluded.checkpoint = 'downloading'
                AND excluded.status = 'downloading'
                AND excluded.downloaded_bytes = 0
                AND excluded.received_bytes = 0
                AND excluded.etag IS NULL
                AND excluded.last_modified IS NULL
              )
            )
            AND (
              download_tasks.checkpoint NOT IN ('completed', 'failed')
              OR excluded.checkpoint = download_tasks.checkpoint
            )
          )
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
      task.operationId,
      task.attemptGeneration,
      task.releaseId,
      task.artifactId,
      task.sourceUrl,
      task.stagingPath,
      task.expectedChecksum,
      task.expectedSizeBytes ?? task.totalBytes,
      _phaseStorageName(task.phase),
      task.retryReason,
      task.effectiveReceivedBytes,
      task.etag,
      task.lastModified,
    ],
  );
}

String _phaseStorageName(ModelDownloadPhase phase) {
  return switch (phase) {
    ModelDownloadPhase.runtimeValidating => 'runtime_validating',
    ModelDownloadPhase.releasingSessions => 'releasing_sessions',
    ModelDownloadPhase.retryableFailed => 'retryable_failed',
    _ => phase.name,
  };
}
