part of 'search_index_service.dart';

extension _SearchIndexWriteOperations on SearchIndexService {
  Future<int> _replacePendingItems({
    required List<SearchIndexPendingItem> items,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
    required _SearchIndexWriteContext writeContext,
  }) async {
    var replacementCount = 0;
    for (final item in items) {
      _validateWriteContext(writeContext);
      final document = item.document;
      if (document == null ||
          item.configurationEpoch != configuration.configurationEpoch ||
          item.modelRevisionHash != modelRevisionHash) {
        throw const EmbeddingIndexStaleWriteException();
      }
      final textChunks = _chunker.chunk(
        document,
        maxChunkLength: configuration.maxChunkLength,
      );
      final now = _clock();
      final setId = _setId(document.sourceKey, activeEmbeddingModel.id);
      final embeddedChunks = <EmbeddingChunk>[];
      int? vectorDimension;
      for (final textChunk in textChunks) {
        late final EmbeddingVector vector;
        try {
          vector = await _embeddingEngine.embed(
            EmbeddingRequest(
              model: activeEmbeddingModel,
              text: textChunk.text,
              cancellationToken: writeContext.cancellationToken,
            ),
          );
        } on EmbeddingCancellationException {
          _validateWriteContext(writeContext);
          rethrow;
        }
        final dimension = vector.values.length;
        if (dimension == 0 ||
            (vectorDimension != null && vectorDimension != dimension)) {
          throw StateError('Embedding vector dimensions are inconsistent.');
        }
        vectorDimension = dimension;
        _validateWriteContext(writeContext);
        final chunkFingerprint = _withFingerprintKey(
          writeContext.sessionKeys,
          (key) => chunkFingerprintBytes(
            key: key,
            sourceType: document.sourceKey.type.name,
            sourceId: document.sourceKey.id,
            sourceField: textChunk.field.wireName,
            fieldChunkIndex: textChunk.fieldChunkIndex,
            text: textChunk.text,
          ),
        );
        embeddedChunks.add(
          EmbeddingChunk(
            id: _chunkId(setId, textChunk.field, textChunk.fieldChunkIndex),
            indexSetId: setId,
            sourceField: textChunk.field,
            fieldChunkIndex: textChunk.fieldChunkIndex,
            chunkFingerprint: chunkFingerprint,
            vectorBlob: Float32VectorCodec.encode(vector.values),
            tokenCount: vector.tokenCount,
            createdAt: now,
          ),
        );
      }
      _validateWriteContext(writeContext);
      final sourceFingerprint = _sourceFingerprint(
        document,
        writeContext.sessionKeys,
      );
      final indexSet = EmbeddingIndexSet(
        id: setId,
        sourceKey: document.sourceKey,
        vaultId: document.vaultId,
        modelId: activeEmbeddingModel.id,
        modelRevisionHash: modelRevisionHash,
        sourceUpdatedAt: document.updatedAt,
        sourceFingerprint: sourceFingerprint,
        fingerprintKeyId: writeContext.sessionKeys.requireKeyId(),
        fingerprintVersion: searchIndexFingerprintVersion,
        indexConfigVersion: searchIndexConfigurationVersion,
        indexConfigEpoch: configuration.configurationEpoch,
        indexConfigHash: searchIndexConfigurationHash(configuration),
        chunkSchemaVersion: 1,
        vectorFormatVersion: float32VectorFormatVersion,
        vectorDimension: vectorDimension ?? 0,
        chunks: embeddedChunks,
        createdAt: now,
      );
      final replaced = await _replaceIndexSet(indexSet, writeContext);
      if (replaced) {
        replacementCount += 1;
      }
    }
    return replacementCount;
  }

  List<int> _sourceFingerprint(
    SearchIndexDocument document, [
    DatabaseSessionKeys? sessionKeys,
  ]) {
    return _withFingerprintKey(
      sessionKeys ?? _keys.requireCurrent(),
      (key) => structuredSourceFingerprintBytes(
        key: key,
        sourceType: document.sourceKey.type.name,
        sourceId: document.sourceKey.id,
        vaultId: document.vaultId,
        fields: document.fields.map(
          (field) => (id: field.field.wireName, values: field.values),
        ),
      ),
    );
  }

  T _withFingerprintKey<T>(
    DatabaseSessionKeys sessionKeys,
    T Function(Uint8List key) consume,
  ) {
    return sessionKeys.withSearchIndexFingerprintKey(consume);
  }

  void _validateSessionKeys(DatabaseSessionKeys expected) {
    DatabaseSessionKeys current;
    try {
      current = _keys.requireCurrent();
    } on StateError {
      throw const EmbeddingIndexStaleWriteException();
    }
    if (!identical(current, expected) || expected.isCleared) {
      throw const EmbeddingIndexStaleWriteException();
    }
  }

  _SearchIndexWriteContext _captureWriteContext() {
    return _SearchIndexWriteContext(
      sessionKeys: _keys.requireCurrent(),
      fenceRevision: _writeFence?.revision,
      writeLease: _writeFence?.acquireLease(),
    );
  }

  void _validateWriteContext(_SearchIndexWriteContext context) {
    _validateSessionKeys(context.sessionKeys);
    final revision = context.fenceRevision;
    if (revision != null) {
      _writeFence!.validate(revision);
    }
  }

  Future<bool> _replaceIndexSet(
    EmbeddingIndexSet indexSet,
    _SearchIndexWriteContext writeContext,
  ) {
    final repository = _repository;
    if (repository is GuardedEmbeddingIndexRepository) {
      final guardedRepository = repository as GuardedEmbeddingIndexRepository;
      return guardedRepository.replaceIndexSetGuarded(
        indexSet,
        validate: () => _validateWriteContext(writeContext),
      );
    }
    _validateWriteContext(writeContext);
    return repository.replaceIndexSet(indexSet);
  }

  DatabaseSessionKeyStore get _keys {
    final store = _sessionKeyStore;
    if (store == null) {
      throw StateError('Search index session keys are unavailable.');
    }
    return store;
  }

  String _setId(SearchSourceKey key, String modelId) {
    final digest = sha256
        .convert(
          utf8.encode(
            '${key.type.name.length}:${key.type.name}'
            '${key.id.length}:${key.id}${modelId.length}:$modelId',
          ),
        )
        .toString();
    return 'embedding-set-$digest';
  }

  String _chunkId(String setId, SearchSourceField field, int fieldChunkIndex) {
    return '$setId:${field.wireName}:$fieldChunkIndex';
  }
}

class _SearchIndexWriteContext {
  const _SearchIndexWriteContext({
    required this.sessionKeys,
    required this.fenceRevision,
    required this.writeLease,
  });

  final DatabaseSessionKeys sessionKeys;
  final int? fenceRevision;
  final SearchIndexWriteLease? writeLease;

  EmbeddingCancellationToken get cancellationToken =>
      writeLease?.cancellationToken ?? EmbeddingCancellationToken.none;

  void release() {
    writeLease?.release();
  }
}
