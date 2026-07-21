part of 'search_index_service.dart';

extension _SearchIndexCorpusOperations on SearchIndexService {
  Future<SearchIndexStatus> _buildCorpusStatus({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required ModelRegistryEntry? activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    if (activeEmbeddingModel == null) {
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

    Future<void> collect(List<SearchIndexDocument> documents) async {
      final headers = await _loadHeaders(documents, activeEmbeddingModel.id);
      for (final document in documents) {
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

    await _forEachCorpusPage(
      activeVaultId: activeVaultId,
      corpus: corpus,
      onSecrets: (items) => collect(<SearchIndexDocument>[
        for (final item in items)
          if (item.vaultId == activeVaultId && item.deletedAt == null)
            _projector.projectSecret(item, policy),
      ]),
      onNotes: (items) => collect(<SearchIndexDocument>[
        for (final item in items)
          if (item.vaultId == activeVaultId && item.deletedAt == null)
            _projector.projectNote(item, policy),
      ]),
    );

    return SearchIndexStatus(
      engineReady: engineState.ready,
      engineReason: engineState.reason,
      hasActiveEmbeddingModel: true,
      pendingItems: pending,
      pendingCount: pendingCount,
    );
  }

  Future<int> _indexCorpusPending({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    if (!configuration.allowLocalEmbedding) {
      await _purgeAllIndexSets();
      return 0;
    }

    final policy = EffectiveSearchPolicy(configuration);
    final configHash = searchIndexConfigurationHash(configuration);
    var replacementCount = 0;

    Future<void> indexDocuments(List<SearchIndexDocument> documents) async {
      final headers = await _loadHeaders(documents, activeEmbeddingModel.id);
      final pending = <SearchIndexPendingItem>[
        for (final document in documents)
          if (_pendingItem(
                document: document,
                current: headers[document.sourceKey],
                modelRevisionHash: modelRevisionHash,
                configuration: configuration,
                configHash: configHash,
              )
              case final item?)
            item,
      ];
      replacementCount += await _replacePendingItems(
        items: pending,
        activeEmbeddingModel: activeEmbeddingModel,
        modelRevisionHash: modelRevisionHash,
        configuration: configuration,
      );
    }

    await _forEachCorpusPage(
      activeVaultId: activeVaultId,
      corpus: corpus,
      onSecrets: (items) => indexDocuments(<SearchIndexDocument>[
        for (final item in items)
          if (item.vaultId == activeVaultId && item.deletedAt == null)
            _projector.projectSecret(item, policy),
      ]),
      onNotes: (items) => indexDocuments(<SearchIndexDocument>[
        for (final item in items)
          if (item.vaultId == activeVaultId && item.deletedAt == null)
            _projector.projectNote(item, policy),
      ]),
    );
    return replacementCount;
  }

  Future<void> _forEachCorpusPage({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required Future<void> Function(List<SecretItem> items) onSecrets,
    required Future<void> Function(List<NoteItem> items) onNotes,
  }) async {
    String? afterSecretId;
    while (true) {
      final page = await corpus.secretPage(
        vaultId: activeVaultId,
        afterId: afterSecretId,
        limit: searchSourcePageSize,
      );
      if (page.isEmpty) {
        break;
      }
      await onSecrets(page);
      afterSecretId = _nextPageCursor(afterSecretId, page.last.id);
    }

    String? afterNoteId;
    while (true) {
      final page = await corpus.notePage(
        vaultId: activeVaultId,
        afterId: afterNoteId,
        limit: searchSourcePageSize,
      );
      if (page.isEmpty) {
        break;
      }
      await onNotes(page);
      afterNoteId = _nextPageCursor(afterNoteId, page.last.id);
    }
  }

  String _nextPageCursor(String? current, String next) {
    if (next.isEmpty || (current != null && next.compareTo(current) <= 0)) {
      throw StateError('Search corpus page did not advance.');
    }
    return next;
  }
}
