part of 'search_index_service_v6_test.dart';

void _runSearchIndexGenerationCases() {
  test(
    'index service writes one field-aware float32 generation without password',
    () async {
      final repository = _RecordingEmbeddingIndexRepository();
      final engine = _RecordingEmbeddingEngine();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'root-key-1',
            searchIndexFingerprintKey: Uint8List.fromList(
              List<int>.generate(32, (index) => index),
            ),
          ),
        );
      addTearDown(keyStore.clear);
      final service = SearchIndexService(
        repository: repository,
        cryptoService: _SearchIndexCryptoService(),
        embeddingEngine: engine,
        sessionKeyStore: keyStore,
        clock: () => DateTime.fromMillisecondsSinceEpoch(10),
      );
      final configuration = SearchConfiguration.defaults().copyWith(
        includePasswordField: true,
      );

      final status = await service.buildStatus(
        secrets: <SecretItem>[_secret()],
        notes: const [],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      expect(status.pendingItems, hasLength(1));
      expect(
        status.pendingItems.single.document?.fields.map(
          (content) => content.field,
        ),
        const <SearchSourceField>[
          SearchSourceField.secretTitle,
          SearchSourceField.secretUsername,
          SearchSourceField.secretWebsiteUrl,
          SearchSourceField.secretNote,
          SearchSourceField.secretTags,
        ],
      );

      await service.indexPendingItems(
        items: status.pendingItems,
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      expect(repository.replacements, hasLength(1));
      final generation = repository.replacements.single;
      expect(generation.sourceKey, const SearchSourceKey.secret('secret-1'));
      expect(generation.fingerprintKeyId, 'root-key-1');
      expect(generation.modelRevisionHash, 'a' * 64);
      expect(generation.vectorDimension, 2);
      expect(
        generation.chunks.map((chunk) => chunk.sourceField),
        const <SearchSourceField>[
          SearchSourceField.secretTitle,
          SearchSourceField.secretUsername,
          SearchSourceField.secretWebsiteUrl,
          SearchSourceField.secretNote,
          SearchSourceField.secretTags,
        ],
      );
      expect(
        Float32VectorCodec.decode(
          generation.chunks.first.vectorBlob,
          expectedDimension: 2,
        ).values,
        const <double>[1, 0],
      );
      expect(engine.texts, isNot(contains('never-index-this-password')));

      repository.current = generation;
      final fresh = await service.buildStatus(
        secrets: <SecretItem>[_secret()],
        notes: const [],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );
      expect(fresh.pendingItems, isEmpty);
    },
  );

  test(
    'non-index source timestamp changes do not invalidate matching content',
    () async {
      final repository = _RecordingEmbeddingIndexRepository();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'root-key-1',
            searchIndexFingerprintKey: Uint8List.fromList(
              List<int>.generate(32, (index) => index),
            ),
          ),
        );
      addTearDown(keyStore.clear);
      final service = SearchIndexService(
        repository: repository,
        cryptoService: _SearchIndexCryptoService(),
        embeddingEngine: _RecordingEmbeddingEngine(),
        sessionKeyStore: keyStore,
      );
      final configuration = SearchConfiguration.defaults();
      final original = _secret();
      final initial = await service.buildStatus(
        secrets: <SecretItem>[original],
        notes: const [],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );
      await service.indexPendingItems(
        items: initial.pendingItems,
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      final timestampOnlyUpdate = SecretItem(
        id: original.id,
        vaultId: original.vaultId,
        title: original.title,
        usernameCiphertext: original.usernameCiphertext,
        passwordCiphertext: original.passwordCiphertext,
        websiteUrlCiphertext: original.websiteUrlCiphertext,
        noteCiphertext: original.noteCiphertext,
        tags: original.tags,
        categoryId: 'category-only-change',
        favorite: true,
        createdAt: original.createdAt,
        updatedAt: original.updatedAt.add(const Duration(seconds: 1)),
      );

      final status = await service.buildStatus(
        secrets: <SecretItem>[timestampOnlyUpdate],
        notes: const [],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      expect(status.pendingItems, isEmpty);
    },
  );

  test(
    'fingerprint key rotation during embedding rejects the stale generation',
    () async {
      final repository = _RecordingEmbeddingIndexRepository();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'root-key-1',
            searchIndexFingerprintKey: Uint8List.fromList(
              List<int>.filled(32, 1),
            ),
          ),
        );
      addTearDown(keyStore.clear);
      final engine = _CallbackEmbeddingEngine(
        onFirstEmbed: () {
          keyStore.replace(
            DatabaseSessionKeys(
              databaseKey: Uint8List(32),
              fieldKey: Uint8List(32),
              keyId: 'root-key-2',
              searchIndexFingerprintKey: Uint8List.fromList(
                List<int>.filled(32, 2),
              ),
            ),
          );
        },
      );
      final service = SearchIndexService(
        repository: repository,
        cryptoService: _SearchIndexCryptoService(),
        embeddingEngine: engine,
        sessionKeyStore: keyStore,
      );
      final configuration = SearchConfiguration.defaults();
      final status = await service.buildStatus(
        secrets: <SecretItem>[_secret()],
        notes: const <NoteItem>[],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      await expectLater(
        service.indexPendingItems(
          items: status.pendingItems,
          activeEmbeddingModel: _model,
          modelRevisionHash: 'a' * 64,
          configuration: configuration,
        ),
        throwsA(isA<EmbeddingIndexStaleWriteException>()),
      );
      expect(repository.replacements, isEmpty);
    },
  );

  test(
    'configuration or model fence invalidation rejects an in-flight generation',
    () async {
      final repository = _RecordingEmbeddingIndexRepository();
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
      final writeFence = SearchIndexWriteFence();
      final service = SearchIndexService(
        repository: repository,
        cryptoService: _SearchIndexCryptoService(),
        embeddingEngine: _CallbackEmbeddingEngine(
          onFirstEmbed: writeFence.invalidate,
        ),
        sessionKeyStore: keyStore,
        writeFence: writeFence,
      );
      final configuration = SearchConfiguration.defaults();
      final status = await service.buildStatus(
        secrets: <SecretItem>[_secret()],
        notes: const <NoteItem>[],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      await expectLater(
        service.indexPendingItems(
          items: status.pendingItems,
          activeEmbeddingModel: _model,
          modelRevisionHash: 'a' * 64,
          configuration: configuration,
        ),
        throwsA(isA<EmbeddingIndexStaleWriteException>()),
      );
      expect(repository.replacements, isEmpty);
    },
  );

  test(
    'write fence cancellation reaches an in-flight embedding request',
    () async {
      final repository = _RecordingEmbeddingIndexRepository();
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
      final writeFence = SearchIndexWriteFence();
      final embeddingEngine = _CancellableEmbeddingEngine();
      final service = SearchIndexService(
        repository: repository,
        cryptoService: _SearchIndexCryptoService(),
        embeddingEngine: embeddingEngine,
        sessionKeyStore: keyStore,
        writeFence: writeFence,
      );
      final configuration = SearchConfiguration.defaults();
      final status = await service.buildStatus(
        secrets: <SecretItem>[_secret()],
        notes: const <NoteItem>[],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      final indexing = service.indexPendingItems(
        items: status.pendingItems,
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );
      await embeddingEngine.started.future;
      writeFence.invalidate();

      await expectLater(
        indexing,
        throwsA(isA<EmbeddingIndexStaleWriteException>()),
      );
      expect(embeddingEngine.cancelled, isTrue);
      expect(repository.replacements, isEmpty);
    },
  );
}
