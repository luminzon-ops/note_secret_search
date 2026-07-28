part of 'search_index_service.dart';

extension _SearchIndexStatusOperations on SearchIndexService {
  Future<SearchIndexStatus> _buildStatus({
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
    required ModelRegistryEntry? activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    if (activeEmbeddingModel == null) {
      await _purgeAllIndexSets();
      return const SearchIndexStatus(
        engineReady: false,
        engineReason: '尚未配置可用的本地 embedding 模型。',
        hasActiveEmbeddingModel: false,
        pendingItems: <SearchIndexPendingItem>[],
      );
    }

    final engineState = await _embeddingEngine.getState(activeEmbeddingModel);
    if (!configuration.allowLocalEmbedding) {
      await _purgeAllIndexSets();
      return SearchIndexStatus(
        engineReady: engineState.ready,
        engineReason: engineState.reason,
        hasActiveEmbeddingModel: true,
        pendingItems: const <SearchIndexPendingItem>[],
      );
    }

    final policy = EffectiveSearchPolicy(configuration);
    final configHash = searchIndexConfigurationHash(configuration);
    final pending = <SearchIndexPendingItem>[];
    var pendingCount = 0;
    final documents = <SearchIndexDocument>[
      for (final secret in secrets)
        if (secret.deletedAt == null) _projector.projectSecret(secret, policy),
      for (final note in notes)
        if (note.deletedAt == null) _projector.projectNote(note, policy),
    ];
    for (
      var offset = 0;
      offset < documents.length;
      offset += embeddingIndexHeaderBatchSize
    ) {
      final batch = documents
          .skip(offset)
          .take(embeddingIndexHeaderBatchSize)
          .toList(growable: false);
      final headers = await _loadHeaders(batch, activeEmbeddingModel.id);
      for (final document in batch) {
        final item = _pendingItem(
          document: document,
          current: headers[document.sourceKey],
          modelRevisionHash: modelRevisionHash,
          configuration: configuration,
          configHash: configHash,
        );
        if (item != null) {
          pendingCount += 1;
          _addPendingPreview(pending, item);
        }
      }
    }

    return SearchIndexStatus(
      engineReady: engineState.ready,
      engineReason: engineState.reason,
      hasActiveEmbeddingModel: true,
      pendingItems: pending,
      pendingCount: pendingCount,
    );
  }

  SearchIndexPendingItem? _pendingItem({
    required SearchIndexDocument document,
    required EmbeddingIndexSetHeader? current,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
    required String configHash,
  }) {
    final sourceFingerprint = _sourceFingerprint(document);
    final keyId = _keys.requireCurrent().requireKeyId();
    if (current != null &&
        current.vaultId == document.vaultId &&
        current.modelRevisionHash == modelRevisionHash &&
        _bytesEqual(current.sourceFingerprint, sourceFingerprint) &&
        current.fingerprintKeyId == keyId &&
        current.fingerprintVersion == searchIndexFingerprintVersion &&
        current.indexConfigVersion == searchIndexConfigurationVersion &&
        current.indexConfigEpoch == configuration.configurationEpoch &&
        current.indexConfigHash == configHash &&
        current.chunkSchemaVersion == 1 &&
        current.vectorFormatVersion == float32VectorFormatVersion) {
      return null;
    }
    return SearchIndexPendingItem(
      sourceId: document.sourceKey.id,
      sourceType: document.sourceKey.type,
      title: document.title,
      updatedAt: document.updatedAt,
      document: document,
      sourceFingerprint: sourceFingerprint,
      configurationEpoch: configuration.configurationEpoch,
      modelRevisionHash: modelRevisionHash,
    );
  }

  Future<Map<SearchSourceKey, EmbeddingIndexSetHeader>> _loadHeaders(
    List<SearchIndexDocument> documents,
    String modelId,
  ) async {
    final repository = _repository;
    if (repository is EmbeddingIndexHeaderRepository) {
      final headerRepository = repository as EmbeddingIndexHeaderRepository;
      return headerRepository.getIndexSetHeadersBySources(
        documents.map((document) => document.sourceKey),
        modelId,
      );
    }

    final headers = <SearchSourceKey, EmbeddingIndexSetHeader>{};
    for (final document in documents) {
      final set = await repository.getIndexSetBySource(
        document.sourceKey,
        modelId,
      );
      if (set != null) {
        headers[document.sourceKey] = EmbeddingIndexSetHeader.fromSet(set);
      }
    }
    return headers;
  }

  void _addPendingPreview(
    List<SearchIndexPendingItem> preview,
    SearchIndexPendingItem item,
  ) {
    preview.add(item);
    preview.sort((left, right) {
      var result = right.updatedAt.compareTo(left.updatedAt);
      result = result != 0
          ? result
          : left.sourceType.index.compareTo(right.sourceType.index);
      return result != 0 ? result : left.sourceId.compareTo(right.sourceId);
    });
    if (preview.length > searchIndexPendingPreviewLimit) {
      preview.removeRange(searchIndexPendingPreviewLimit, preview.length);
    }
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

  Future<void> _purgeAllIndexSets() async {
    final repository = _corpusRepository;
    if (repository == null) {
      return;
    }
    while (await repository.purgeAllIndexSets(batchSize: 100) == 100) {}
  }

  Future<void> _purgeIncompatibleIndexSets({
    required String activeVaultId,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    final repository = _corpusRepository;
    if (repository == null) {
      return;
    }
    final compatibility = EmbeddingIndexCompatibility(
      vaultId: activeVaultId,
      modelId: activeEmbeddingModel.id,
      modelRevisionHash: modelRevisionHash,
      fingerprintKeyId: _keys.requireCurrent().requireKeyId(),
      fingerprintVersion: searchIndexFingerprintVersion,
      indexConfigVersion: searchIndexConfigurationVersion,
      indexConfigEpoch: configuration.configurationEpoch,
      indexConfigHash: searchIndexConfigurationHash(configuration),
      chunkSchemaVersion: 1,
      vectorFormatVersion: float32VectorFormatVersion,
    );
    while (await repository.purgeIncompatibleIndexSets(
          compatibility,
          batchSize: 100,
        ) ==
        100) {}
  }
}
