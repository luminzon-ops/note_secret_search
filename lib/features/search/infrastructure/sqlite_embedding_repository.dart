import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteEmbeddingRepository {
  SqliteEmbeddingRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  Future<List<EmbeddingChunk>> getChunksBySource(
    String sourceId,
    SearchSourceType sourceType,
    String modelId,
  ) async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.embeddingChunks,
      where: 'source_id = ? AND source_type = ? AND model_id = ?',
      whereArgs: <Object>[sourceId, sourceType.name, modelId],
      orderBy: 'chunk_index ASC',
    );

    return rows.map(_mapChunk).toList(growable: false);
  }

  Future<void> upsertEmbeddingChunks(List<EmbeddingChunk> chunks) async {
    if (chunks.isEmpty) {
      return;
    }

    final db = await _database.database;
    await db.transaction((txn) async {
      for (final chunk in chunks) {
        await txn.insert(
          DatabaseSchema.embeddingChunks,
          <String, Object?>{
            'id': chunk.id,
            'source_id': chunk.sourceId,
            'source_type': chunk.sourceType.name,
            'chunk_index': chunk.chunkIndex,
            'plaintext_hash': chunk.plainTextHash,
            'model_id': chunk.modelId,
            'vector_blob': chunk.vectorBlob,
            'token_count': chunk.tokenCount,
            'created_at': chunk.createdAt.millisecondsSinceEpoch,
            'updated_at': chunk.updatedAt.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> removeChunksBySource(String sourceId, SearchSourceType sourceType) async {
    final db = await _database.database;
    await db.delete(
      DatabaseSchema.embeddingChunks,
      where: 'source_id = ? AND source_type = ?',
      whereArgs: <Object>[sourceId, sourceType.name],
    );
  }

  EmbeddingChunk _mapChunk(Map<String, Object?> row) {
    return EmbeddingChunk(
      id: row['id']! as String,
      sourceType: SearchSourceType.values.firstWhere(
        (value) => value.name == row['source_type']! as String,
      ),
      sourceId: row['source_id']! as String,
      chunkIndex: row['chunk_index']! as int,
      plainTextHash: row['plaintext_hash']! as String,
      modelId: row['model_id']! as String,
      vectorBlob: row['vector_blob'] as List<int>?,
      tokenCount: row['token_count'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    );
  }
}
