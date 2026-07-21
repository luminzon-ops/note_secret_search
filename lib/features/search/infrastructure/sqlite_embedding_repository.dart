import 'dart:async';

import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_corpus_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

enum EmbeddingReplacementCheckpoint {
  oldGenerationDeleted,
  indexSetInserted,
  chunksInserted,
}

typedef EmbeddingReplacementCheckpointCallback =
    FutureOr<void> Function(EmbeddingReplacementCheckpoint checkpoint);

class SqliteEmbeddingRepository
    implements
        EmbeddingIndexRepository,
        EmbeddingIndexHeaderRepository,
        EmbeddingIndexCorpusRepository {
  SqliteEmbeddingRepository({
    required AppDatabase database,
    EmbeddingReplacementCheckpointCallback? onReplacementCheckpoint,
  }) : _database = database,
       _onReplacementCheckpoint = onReplacementCheckpoint;

  final AppDatabase _database;
  final EmbeddingReplacementCheckpointCallback? _onReplacementCheckpoint;

  SqliteEmbeddingCorpusRepository get _corpus {
    return SqliteEmbeddingCorpusRepository(database: _database);
  }

  @override
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  ) {
    return _database.run(
      (database) => _loadIndexSet(database, sourceKey, modelId),
    );
  }

  @override
  Future<Map<SearchSourceKey, EmbeddingIndexSetHeader>>
  getIndexSetHeadersBySources(
    Iterable<SearchSourceKey> sourceKeys,
    String modelId,
  ) {
    final keys = sourceKeys.toSet().toList(growable: false);
    if (keys.isEmpty) {
      return Future<Map<SearchSourceKey, EmbeddingIndexSetHeader>>.value(
        const <SearchSourceKey, EmbeddingIndexSetHeader>{},
      );
    }
    if (keys.length > embeddingIndexHeaderBatchSize) {
      throw ArgumentError.value(
        keys.length,
        'sourceKeys',
        'Maximum is $embeddingIndexHeaderBatchSize.',
      );
    }
    final secretIds = <String>[
      for (final key in keys)
        if (key.type == SearchSourceType.secret) key.id,
    ];
    final noteIds = <String>[
      for (final key in keys)
        if (key.type == SearchSourceType.note) key.id,
    ];
    final clauses = <String>[];
    final arguments = <Object>[modelId];
    if (secretIds.isNotEmpty) {
      clauses.add(
        "(source_type = 'secret' AND source_id IN "
        "(${List<String>.filled(secretIds.length, '?').join(', ')}))",
      );
      arguments.addAll(secretIds);
    }
    if (noteIds.isNotEmpty) {
      clauses.add(
        "(source_type = 'note' AND source_id IN "
        "(${List<String>.filled(noteIds.length, '?').join(', ')}))",
      );
      arguments.addAll(noteIds);
    }
    return _database.run((database) async {
      final rows = await database.query(
        DatabaseSchema.embeddingIndexSets,
        where: 'model_id = ? AND (${clauses.join(' OR ')})',
        whereArgs: arguments,
        orderBy: 'source_type ASC, source_id ASC',
      );
      return <SearchSourceKey, EmbeddingIndexSetHeader>{
        for (final row in rows) _sourceKey(row): _mapHeader(row),
      };
    });
  }

  @override
  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet) {
    return _database.transaction((database) async {
      await _validateOwners(database, indexSet);
      final existing = await _loadIndexSet(
        database,
        indexSet.sourceKey,
        indexSet.modelId,
      );
      if (existing != null && _sameGeneration(existing, indexSet)) {
        return false;
      }

      await database.delete(
        DatabaseSchema.embeddingIndexSets,
        where: 'source_type = ? AND source_id = ?',
        whereArgs: <Object>[
          indexSet.sourceKey.type.name,
          indexSet.sourceKey.id,
        ],
      );
      await _checkpoint(EmbeddingReplacementCheckpoint.oldGenerationDeleted);
      await database.insert(
        DatabaseSchema.embeddingIndexSets,
        _indexSetRow(indexSet),
      );
      await _checkpoint(EmbeddingReplacementCheckpoint.indexSetInserted);

      for (final chunk in indexSet.chunks) {
        await database.insert(DatabaseSchema.embeddingChunks, _chunkRow(chunk));
      }
      await _checkpoint(EmbeddingReplacementCheckpoint.chunksInserted);

      final count = await database.rawQuery(
        'SELECT COUNT(*) AS count FROM ${DatabaseSchema.embeddingChunks} '
        'WHERE index_set_id = ?',
        <Object>[indexSet.id],
      );
      if (count.single['count'] != indexSet.chunkCount) {
        throw StateError('Embedding generation chunk count mismatch.');
      }
      return true;
    });
  }

  @override
  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey) {
    return _database.run((database) {
      return database.delete(
        DatabaseSchema.embeddingIndexSets,
        where: 'source_type = ? AND source_id = ?',
        whereArgs: <Object>[sourceKey.type.name, sourceKey.id],
      );
    });
  }

  @override
  Future<List<EmbeddingIndexSet>> getCompatibleIndexSets(
    EmbeddingIndexCompatibility compatibility, {
    String? afterId,
    int limit = 100,
  }) {
    return _corpus.getCompatibleIndexSets(
      compatibility,
      afterId: afterId,
      limit: limit,
    );
  }

  @override
  Future<int> purgeIncompatibleIndexSets(
    EmbeddingIndexCompatibility compatibility, {
    int batchSize = 100,
  }) {
    return _corpus.purgeIncompatibleIndexSets(
      compatibility,
      batchSize: batchSize,
    );
  }

  @override
  Future<int> purgeIndexSetsByIds(Iterable<String> indexSetIds) {
    return _corpus.purgeIndexSetsByIds(indexSetIds);
  }

  @override
  Future<int> purgeAllIndexSets({int batchSize = 100}) {
    return _corpus.purgeAllIndexSets(batchSize: batchSize);
  }

  Future<EmbeddingIndexSet?> _loadIndexSet(
    DatabaseExecutor database,
    SearchSourceKey sourceKey,
    String modelId,
  ) async {
    final sets = await database.query(
      DatabaseSchema.embeddingIndexSets,
      where: 'source_type = ? AND source_id = ? AND model_id = ?',
      whereArgs: <Object>[sourceKey.type.name, sourceKey.id, modelId],
      limit: 1,
    );
    if (sets.isEmpty) {
      return null;
    }

    final set = sets.single;
    final chunkRows = await database.query(
      DatabaseSchema.embeddingChunks,
      where: 'index_set_id = ?',
      whereArgs: <Object>[set['id']! as String],
      orderBy: 'source_field ASC, field_chunk_index ASC',
    );
    return EmbeddingIndexSet(
      id: set['id']! as String,
      sourceKey: SearchSourceKey(
        type: SearchSourceType.parse(set['source_type']! as String),
        id: set['source_id']! as String,
      ),
      vaultId: set['vault_id']! as String,
      modelId: set['model_id']! as String,
      modelRevisionHash: set['model_revision_hash']! as String,
      sourceUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
        set['source_updated_at']! as int,
      ),
      sourceFingerprint: set['source_fingerprint']! as List<int>,
      fingerprintKeyId: set['fingerprint_key_id']! as String,
      fingerprintVersion: set['fingerprint_version']! as int,
      indexConfigVersion: set['index_config_version']! as int,
      indexConfigEpoch: set['index_config_epoch']! as int,
      indexConfigHash: set['index_config_hash']! as String,
      chunkSchemaVersion: set['chunk_schema_version']! as int,
      vectorFormatVersion: set['vector_format_version']! as int,
      vectorDimension: set['vector_dimension']! as int,
      chunks: chunkRows.map(_mapIndexChunk).toList(growable: false),
      createdAt: DateTime.fromMillisecondsSinceEpoch(set['created_at']! as int),
    );
  }

  EmbeddingChunk _mapIndexChunk(Map<String, Object?> row) {
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

  EmbeddingIndexSetHeader _mapHeader(Map<String, Object?> row) {
    return EmbeddingIndexSetHeader(
      id: row['id']! as String,
      sourceKey: _sourceKey(row),
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
      chunkCount: row['chunk_count']! as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  SearchSourceKey _sourceKey(Map<String, Object?> row) {
    return SearchSourceKey(
      type: SearchSourceType.parse(row['source_type']! as String),
      id: row['source_id']! as String,
    );
  }

  Future<void> _validateOwners(
    DatabaseExecutor database,
    EmbeddingIndexSet indexSet,
  ) async {
    final sourceTable = switch (indexSet.sourceKey.type) {
      SearchSourceType.secret => DatabaseSchema.secretItems,
      SearchSourceType.note => DatabaseSchema.noteItems,
    };
    final sources = await database.query(
      sourceTable,
      columns: const <String>['vault_id', 'updated_at', 'deleted_at'],
      where: 'id = ?',
      whereArgs: <Object>[indexSet.sourceKey.id],
      limit: 1,
    );
    if (sources.isEmpty) {
      throw const EmbeddingIndexStaleWriteException();
    }
    final source = sources.single;
    if (source['vault_id'] != indexSet.vaultId ||
        source['deleted_at'] != null ||
        source['updated_at'] !=
            indexSet.sourceUpdatedAt.millisecondsSinceEpoch) {
      throw const EmbeddingIndexStaleWriteException();
    }

    final models = await database.query(
      DatabaseSchema.modelRegistry,
      columns: const <String>['type'],
      where: 'id = ?',
      whereArgs: <Object>[indexSet.modelId],
      limit: 1,
    );
    if (models.isEmpty || models.single['type'] != 'embedding') {
      throw const EmbeddingIndexStaleWriteException();
    }
  }

  Map<String, Object?> _indexSetRow(EmbeddingIndexSet indexSet) {
    return <String, Object?>{
      'id': indexSet.id,
      'source_type': indexSet.sourceKey.type.name,
      'source_id': indexSet.sourceKey.id,
      'vault_id': indexSet.vaultId,
      'model_id': indexSet.modelId,
      'model_revision_hash': indexSet.modelRevisionHash,
      'source_updated_at': indexSet.sourceUpdatedAt.millisecondsSinceEpoch,
      'source_fingerprint': indexSet.sourceFingerprint,
      'fingerprint_key_id': indexSet.fingerprintKeyId,
      'fingerprint_version': indexSet.fingerprintVersion,
      'index_config_version': indexSet.indexConfigVersion,
      'index_config_epoch': indexSet.indexConfigEpoch,
      'index_config_hash': indexSet.indexConfigHash,
      'chunk_schema_version': indexSet.chunkSchemaVersion,
      'vector_format_version': indexSet.vectorFormatVersion,
      'vector_dimension': indexSet.vectorDimension,
      'chunk_count': indexSet.chunkCount,
      'created_at': indexSet.createdAt.millisecondsSinceEpoch,
    };
  }

  Map<String, Object?> _chunkRow(EmbeddingChunk chunk) {
    return <String, Object?>{
      'id': chunk.id,
      'index_set_id': chunk.indexSetId,
      'source_field': chunk.sourceField.wireName,
      'field_chunk_index': chunk.fieldChunkIndex,
      'chunk_fingerprint': chunk.chunkFingerprint,
      'vector_blob': chunk.vectorBlob,
      'token_count': chunk.tokenCount,
      'created_at': chunk.createdAt.millisecondsSinceEpoch,
    };
  }

  bool _sameGeneration(EmbeddingIndexSet left, EmbeddingIndexSet right) {
    if (left.sourceKey != right.sourceKey ||
        left.vaultId != right.vaultId ||
        left.modelId != right.modelId ||
        left.modelRevisionHash != right.modelRevisionHash ||
        left.sourceUpdatedAt != right.sourceUpdatedAt ||
        !_bytesEqual(left.sourceFingerprint, right.sourceFingerprint) ||
        left.fingerprintKeyId != right.fingerprintKeyId ||
        left.fingerprintVersion != right.fingerprintVersion ||
        left.indexConfigVersion != right.indexConfigVersion ||
        left.indexConfigEpoch != right.indexConfigEpoch ||
        left.indexConfigHash != right.indexConfigHash ||
        left.chunkSchemaVersion != right.chunkSchemaVersion ||
        left.vectorFormatVersion != right.vectorFormatVersion ||
        left.vectorDimension != right.vectorDimension ||
        left.chunkCount != right.chunkCount) {
      return false;
    }

    final leftChunks = <String, EmbeddingChunk>{
      for (final chunk in left.chunks) _coordinate(chunk): chunk,
    };
    for (final chunk in right.chunks) {
      final other = leftChunks[_coordinate(chunk)];
      if (other == null ||
          !_bytesEqual(other.chunkFingerprint, chunk.chunkFingerprint) ||
          !_bytesEqual(other.vectorBlob, chunk.vectorBlob) ||
          other.tokenCount != chunk.tokenCount) {
        return false;
      }
    }
    return true;
  }

  String _coordinate(EmbeddingChunk chunk) {
    return '${chunk.sourceField.wireName}:${chunk.fieldChunkIndex}';
  }

  bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _checkpoint(EmbeddingReplacementCheckpoint checkpoint) async {
    await _onReplacementCheckpoint?.call(checkpoint);
  }
}
