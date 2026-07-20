import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteEmbeddingCorpusRepository
    implements EmbeddingIndexCorpusRepository {
  const SqliteEmbeddingCorpusRepository({required AppDatabase database})
    : _database = database;

  final AppDatabase _database;

  @override
  Future<List<EmbeddingIndexSet>> getCompatibleIndexSets(
    EmbeddingIndexCompatibility compatibility, {
    String? afterId,
    int limit = 100,
  }) {
    _validateBatchSize(limit);
    return _database.run((database) async {
      final predicate = _compatibilityPredicate(compatibility);
      final rows = await database.query(
        DatabaseSchema.embeddingIndexSets,
        where: afterId == null ? predicate.sql : '${predicate.sql} AND id > ?',
        whereArgs: <Object>[
          ...predicate.arguments,
          if (afterId != null) afterId,
        ],
        orderBy: 'id ASC',
        limit: limit,
      );
      if (rows.isEmpty) {
        return const <EmbeddingIndexSet>[];
      }

      final ids = rows
          .map((row) => row['id']! as String)
          .toList(growable: false);
      final chunkRows = await database.query(
        DatabaseSchema.embeddingChunks,
        where: 'index_set_id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
        orderBy: 'index_set_id ASC, source_field ASC, field_chunk_index ASC',
      );
      final chunksBySet = <String, List<EmbeddingChunk>>{};
      for (final row in chunkRows) {
        final setId = row['index_set_id']! as String;
        chunksBySet
            .putIfAbsent(setId, () => <EmbeddingChunk>[])
            .add(_mapChunk(row));
      }
      return rows
          .map(
            (row) => _mapSet(
              row,
              chunksBySet[row['id']! as String] ?? const <EmbeddingChunk>[],
            ),
          )
          .toList(growable: false);
    });
  }

  @override
  Future<int> purgeIncompatibleIndexSets(
    EmbeddingIndexCompatibility compatibility, {
    int batchSize = 100,
  }) {
    _validateBatchSize(batchSize);
    return _database.transaction((database) async {
      final predicate = _compatibilityPredicate(compatibility);
      final rows = await database.query(
        DatabaseSchema.embeddingIndexSets,
        columns: const <String>['id'],
        where: 'NOT (${predicate.sql})',
        whereArgs: predicate.arguments,
        orderBy: 'id ASC',
        limit: batchSize,
      );
      return _deleteIds(database, rows.map((row) => row['id']! as String));
    });
  }

  @override
  Future<int> purgeIndexSetsByIds(Iterable<String> indexSetIds) {
    final ids = indexSetIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return Future<int>.value(0);
    }
    if (ids.length > 100) {
      throw ArgumentError.value(ids.length, 'indexSetIds', 'Maximum is 100.');
    }
    return _database.transaction((database) => _deleteIds(database, ids));
  }

  @override
  Future<int> purgeAllIndexSets({int batchSize = 100}) {
    _validateBatchSize(batchSize);
    return _database.transaction((database) async {
      final rows = await database.query(
        DatabaseSchema.embeddingIndexSets,
        columns: const <String>['id'],
        orderBy: 'id ASC',
        limit: batchSize,
      );
      return _deleteIds(database, rows.map((row) => row['id']! as String));
    });
  }

  _SqlPredicate _compatibilityPredicate(
    EmbeddingIndexCompatibility compatibility,
  ) {
    return _SqlPredicate(
      '''
vault_id = ? AND model_id = ? AND model_revision_hash = ?
AND fingerprint_key_id = ? AND fingerprint_version = ?
AND index_config_version = ? AND index_config_epoch = ?
AND index_config_hash = ? AND chunk_schema_version = ?
AND vector_format_version = ?
'''
          .trim(),
      <Object>[
        compatibility.vaultId,
        compatibility.modelId,
        compatibility.modelRevisionHash,
        compatibility.fingerprintKeyId,
        compatibility.fingerprintVersion,
        compatibility.indexConfigVersion,
        compatibility.indexConfigEpoch,
        compatibility.indexConfigHash,
        compatibility.chunkSchemaVersion,
        compatibility.vectorFormatVersion,
      ],
    );
  }

  EmbeddingIndexSet _mapSet(
    Map<String, Object?> row,
    List<EmbeddingChunk> chunks,
  ) {
    if (row['chunk_count'] != chunks.length) {
      throw const FormatException('Embedding generation chunk count mismatch.');
    }
    return EmbeddingIndexSet(
      id: row['id']! as String,
      sourceKey: SearchSourceKey(
        type: SearchSourceType.parse(row['source_type']! as String),
        id: row['source_id']! as String,
      ),
      vaultId: row['vault_id']! as String,
      modelId: row['model_id']! as String,
      modelRevisionHash: row['model_revision_hash']! as String,
      sourceUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['source_updated_at']! as int,
      ),
      sourceFingerprint: row['source_fingerprint']! as List<int>,
      fingerprintKeyId: row['fingerprint_key_id']! as String,
      fingerprintVersion: row['fingerprint_version']! as int,
      indexConfigVersion: row['index_config_version']! as int,
      indexConfigEpoch: row['index_config_epoch']! as int,
      indexConfigHash: row['index_config_hash']! as String,
      chunkSchemaVersion: row['chunk_schema_version']! as int,
      vectorFormatVersion: row['vector_format_version']! as int,
      vectorDimension: row['vector_dimension']! as int,
      chunks: chunks,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  EmbeddingChunk _mapChunk(Map<String, Object?> row) {
    return EmbeddingChunk(
      id: row['id']! as String,
      indexSetId: row['index_set_id']! as String,
      sourceField: SearchSourceField.parse(row['source_field']! as String),
      fieldChunkIndex: row['field_chunk_index']! as int,
      chunkFingerprint: row['chunk_fingerprint']! as List<int>,
      vectorBlob: row['vector_blob']! as List<int>,
      tokenCount: row['token_count'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  Future<int> _deleteIds(
    DatabaseExecutor database,
    Iterable<String> indexSetIds,
  ) {
    final ids = indexSetIds.toList(growable: false);
    if (ids.isEmpty) {
      return Future<int>.value(0);
    }
    return database.delete(
      DatabaseSchema.embeddingIndexSets,
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  void _validateBatchSize(int value) {
    if (value < 1 || value > 100) {
      throw ArgumentError.value(
        value,
        'batchSize',
        'Must be between 1 and 100.',
      );
    }
  }
}

class _SqlPredicate {
  const _SqlPredicate(this.sql, this.arguments);

  final String sql;
  final List<Object> arguments;
}
