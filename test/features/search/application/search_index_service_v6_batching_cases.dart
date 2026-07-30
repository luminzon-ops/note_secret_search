part of 'search_index_service_v6_test.dart';

void _runSearchIndexBatchingCases() {
  test('index status reads generation headers in 200-source batches', () async {
    final repository = _BatchHeaderRepository();
    final keyStore = DatabaseSessionKeyStore()
      ..replace(
        DatabaseSessionKeys(
          databaseKey: Uint8List(32),
          fieldKey: Uint8List(32),
          keyId: 'root-key-1',
          searchIndexFingerprintKey: Uint8List(32),
        ),
      );
    addTearDown(keyStore.clear);
    final service = SearchIndexService(
      repository: repository,
      cryptoService: _SearchIndexCryptoService(),
      embeddingEngine: _RecordingEmbeddingEngine(),
      sessionKeyStore: keyStore,
    );

    final status = await service.buildStatus(
      secrets: <SecretItem>[
        for (var index = 0; index < 401; index++)
          _secret(id: 'secret-${index.toString().padLeft(3, '0')}'),
      ],
      notes: const <NoteItem>[],
      activeEmbeddingModel: _model,
      modelRevisionHash: 'a' * 64,
      configuration: SearchConfiguration.defaults(),
    );

    expect(status.pendingCount, 401);
    expect(status.pendingItems, hasLength(searchIndexPendingPreviewLimit));
    expect(repository.headerBatchSizes, const <int>[200, 200, 1]);
    expect(repository.fullGenerationReads, 0);
  });
}
