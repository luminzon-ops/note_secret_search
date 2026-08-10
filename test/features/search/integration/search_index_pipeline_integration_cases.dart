part of 'search_index_pipeline_integration_test.dart';

void _runSearchIndexPipelineIntegrationCases() {
  test(
    'production pipeline preserves field identity scope ranking and typed AI context',
    () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'search.scope.include_password_field': true,
      });
      final database = await openTestAppDatabase();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List.fromList(
              List<int>.generate(32, (index) => 0x20 + index),
            ),
            fieldKey: Uint8List.fromList(
              List<int>.generate(32, (index) => 0x60 + index),
            ),
            keyId: 'phase4-key',
            searchIndexFingerprintKey: Uint8List.fromList(
              List<int>.generate(32, (index) => 0xa0 + index),
            ),
          ),
        );
      final crypto = AesGcmFieldCrypto(
        sessionKeyStore: keyStore,
        nonceSource: _IncrementingNonceSource(),
      );
      final engine = _DeterministicEmbeddingEngine();
      final vaultRepository = SqliteVaultRepository(database: database);
      final secretRepository = SqliteSecretRepository(database: database);
      final noteRepository = SqliteNoteRepository(database: database);
      final embeddingRepository = SqliteEmbeddingRepository(database: database);

      addTearDown(() async {
        keyStore.clear();
        await database.close();
      });

      await SqliteModelRegistryRepository(
        database: database,
      ).save(_embeddingModel);
      await secretRepository.save(_secret(crypto));
      for (final note in _notes(crypto)) {
        await noteRepository.save(note);
      }

      final preferences = await SharedPreferences.getInstance();
      final protectedRepository = SqliteProtectedConfigurationRepository(
        database: database,
        cryptoService: crypto,
      );
      final configurationRepository = SqliteSearchConfigurationRepository(
        preferences: preferences,
        loadAppSetting: protectedRepository.loadAppSetting,
        saveAppSetting: protectedRepository.saveAppSetting,
      );
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          databaseSessionKeyStoreProvider.overrideWithValue(keyStore),
          cryptoServiceProvider.overrideWithValue(crypto),
          embeddingEngineProvider.overrideWithValue(engine),
          sqliteEmbeddingRepositoryProvider.overrideWithValue(
            embeddingRepository,
          ),
          searchConfigurationRepositoryProvider.overrideWith(
            (ref) async => configurationRepository,
          ),
          vaultRepositoryProvider.overrideWithValue(vaultRepository),
          noteRepositoryProvider.overrideWithValue(noteRepository),
          secretRepositoryProvider.overrideWithValue(secretRepository),
          sharedPreferencesProvider.overrideWith((ref) async => preferences),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          semanticSearchReadinessProvider.overrideWith(
            (ref) async => const SemanticSearchReadiness(
              ready: true,
              reason: 'ready',
              activeEmbeddingModel: _embeddingModel,
              runtimeStatus: EmbeddingRuntimeStatus.ready,
              runtimeState: EmbeddingEngineState(
                ready: true,
                reason: 'ready',
                status: EmbeddingRuntimeStatus.ready,
                vectorDimension: 2,
              ),
            ),
          ),
          searchIndexModelRevisionProvider(
            _embeddingModel,
          ).overrideWith((ref) async => _modelRevision),
        ],
      );
      addTearDown(container.dispose);

      final configuration = await container.read(
        searchConfigurationProvider.future,
      );
      expect(configuration.includePasswordField, isTrue);
      final secrets = await container.read(secretListProvider.future);
      final notes = await container.read(noteListProvider.future);
      expect(secrets, hasLength(1));
      expect(notes, hasLength(6));

      final indexService = container.read(searchIndexServiceProvider);
      final status = await indexService.buildStatus(
        secrets: secrets,
        notes: notes,
        activeEmbeddingModel: _embeddingModel,
        modelRevisionHash: _modelRevision,
        configuration: configuration,
      );
      expect(status.pendingItems, hasLength(7));

      await indexService.indexPendingItems(
        items: status.pendingItems,
        activeEmbeddingModel: _embeddingModel,
        modelRevisionHash: _modelRevision,
        configuration: configuration,
      );

      final storedChunks = await database.run(
        (db) => db.rawQuery('''
          SELECT index_set.source_type, index_set.source_id,
                 chunk.source_field, chunk.vector_blob
          FROM ${DatabaseSchema.embeddingChunks} chunk
          JOIN ${DatabaseSchema.embeddingIndexSets} index_set
            ON index_set.id = chunk.index_set_id
          ORDER BY index_set.source_type, index_set.source_id,
                   chunk.source_field, chunk.field_chunk_index
          '''),
      );
      expect(
        storedChunks
            .where((row) => row['source_id'] == _sharedSourceId)
            .map((row) => row['source_field']),
        containsAll(<String>[
          'secret.title',
          'secret.username',
          'secret.website_url',
          'secret.note',
          'secret.tags',
          'note.title',
          'note.summary',
          'note.body',
          'note.tags',
        ]),
      );
      expect(
        storedChunks.map((row) => row['source_field']),
        isNot(contains('secret.password')),
      );
      expect(
        storedChunks.every(
          (row) => (row['vector_blob']! as List<int>).length == 8,
        ),
        isTrue,
      );
      expect(engine.indexedTexts, isNot(contains('password-only-value')));

      final freshStatus = await indexService.buildStatus(
        secrets: secrets,
        notes: notes,
        activeEmbeddingModel: _embeddingModel,
        modelRevisionHash: _modelRevision,
        configuration: configuration,
      );
      expect(freshStatus.pendingItems, isEmpty);

      await _insertStaleGenerations(
        database: database,
        configuration: configuration,
      );

      container.read(searchQueryProvider.notifier).state = 'alice@example.test';
      final semantic = await container.read(
        semanticSearchResultsProvider.future,
      );
      final sharedSecret = semantic.singleWhere(
        (result) =>
            result.item.type == SearchResultType.secret &&
            result.item.id == _sharedSourceId,
      );
      final sharedNote = semantic.singleWhere(
        (result) =>
            result.item.type == SearchResultType.note &&
            result.item.id == _sharedSourceId,
      );
      expect(
        sharedSecret.evidence.first.sourceField,
        SearchSourceField.secretUsername,
      );
      expect(sharedSecret.primaryRawSimilarity, closeTo(1, 0.000001));
      expect(sharedSecret.score, closeTo(1.10, 0.000001));
      expect(
        sharedNote.evidence.first.sourceField,
        SearchSourceField.noteSummary,
      );
      expect(sharedNote.primaryRawSimilarity, closeTo(0.98, 0.0001));
      expect(sharedNote.score, closeTo(1.078, 0.0001));

      final staleCount = await database.run(
        (db) => db.rawQuery(
          '''
          SELECT COUNT(*) AS count
          FROM ${DatabaseSchema.embeddingIndexSets}
          WHERE model_revision_hash = ?
          ''',
          <Object>[_staleModelRevision],
        ),
      );
      expect(staleCount.single['count'], 0);

      final unified = await container.read(unifiedSearchResultsProvider.future);
      expect(unified, hasLength(6));
      expect(
        (type: unified.first.type, id: unified.first.id),
        (type: SearchResultType.secret, id: _sharedSourceId),
      );
      expect(unified.first.matchSources, <SearchMatchSource>{
        SearchMatchSource.keyword,
        SearchMatchSource.semantic,
      });
      expect(
        unified
            .where((item) => item.id == _sharedSourceId)
            .map((item) => item.type),
        <SearchResultType>[SearchResultType.secret, SearchResultType.note],
      );

      final context = await container
          .read(aiChatContextRetrieverProvider)
          .retrieve(
            query: 'alice@example.test',
            embeddingModel: _embeddingModel,
          );
      expect(context, hasLength(5));
      expect(
        context
            .where((item) => item.id == _sharedSourceId)
            .map((item) => item.type),
        <ChatContextItemType>[
          ChatContextItemType.secret,
          ChatContextItemType.note,
        ],
      );
      expect(context.map((item) => item.id), isNot(contains('candidate-4')));

      final weakAssistContext = await container
          .read(aiChatContextRetrieverProvider)
          .retrieve(
            query: 'weak-assist-query',
            embeddingModel: _embeddingModel,
          );
      expect(weakAssistContext, isEmpty);

      container.read(searchQueryProvider.notifier).state =
          'password-only-value';
      final passwordResults = await container.read(
        unifiedSearchResultsProvider.future,
      );
      expect(passwordResults, hasLength(1));
      expect(passwordResults.single.type, SearchResultType.secret);
      expect(passwordResults.single.keywordHitFields, <SearchSourceField>[
        SearchSourceField.secretPassword,
      ]);
      expect(passwordResults.single.matchSources, <SearchMatchSource>{
        SearchMatchSource.keyword,
      });
    },
  );
}
