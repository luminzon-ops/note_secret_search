import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteModelDownloadRepository implements ModelDownloadRepository {
  SqliteModelDownloadRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  @override
  Future<ModelDownloadTask?> findLatestTaskByModel(String modelId) async {
    final db = await _database.database;
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
  }

  @override
  Future<ModelDownloadTask?> findLatestTaskByModelAndSource(String modelId, String sourceId) async {
    final db = await _database.database;
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
  }

  @override
  Future<List<ModelDownloadTask>> listTasks() async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.downloadTasks,
      orderBy: 'updated_at DESC',
    );

    return rows.map(_mapTask).toList(growable: false);
  }

  @override
  Future<void> saveTask(ModelDownloadTask task) async {
    final db = await _database.database;
    await db.insert(
      DatabaseSchema.downloadTasks,
      <String, Object?>{
        'id': task.id,
        'model_id': task.modelId,
        'source_id': task.sourceId,
        'status': task.status.name,
        'total_bytes': task.totalBytes,
        'downloaded_bytes': task.downloadedBytes,
        'average_speed': task.averageSpeed,
        'error_message': task.errorMessage,
        'resumable': task.resumable ? 1 : 0,
        'created_at': task.createdAt.millisecondsSinceEpoch,
        'updated_at': task.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
