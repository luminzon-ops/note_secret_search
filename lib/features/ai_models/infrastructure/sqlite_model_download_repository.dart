import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';

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
    return _database.run((db) async {
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
    });
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
    );
  }

  ModelDownloadStatus _parseStatus(String raw) {
    return ModelDownloadStatus.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ModelDownloadStatus.idle,
    );
  }
}
