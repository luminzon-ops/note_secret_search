part of 'sqlite_embedding_repository_test.dart';

void _runSqliteEmbeddingReplaceReadCases() {
  test(
    'replacement removes the complete old generation including tail chunks',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database);
      final repository = SqliteEmbeddingRepository(database: database);

      expect(
        await repository.replaceIndexSet(
          _generation(
            id: 'set-old',
            fields: const <SearchSourceField>[
              SearchSourceField.secretTitle,
              SearchSourceField.secretNote,
            ],
          ),
        ),
        isTrue,
      );
      expect(
        await repository.replaceIndexSet(
          _generation(
            id: 'set-new',
            fields: const <SearchSourceField>[SearchSourceField.secretTitle],
          ),
        ),
        isTrue,
      );

      final restored = await repository.getIndexSetBySource(
        const SearchSourceKey.secret('secret-1'),
        'model-1',
      );
      expect(restored?.id, 'set-new');
      expect(restored?.chunkCount, 1);
      expect(
        restored?.chunks.single.sourceField,
        SearchSourceField.secretTitle,
      );
    },
  );

  test(
    'failed replacement rolls back to the old complete generation',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database);
      final repository = SqliteEmbeddingRepository(database: database);
      await repository.replaceIndexSet(
        _generation(
          id: 'set-old',
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );
      final failing = SqliteEmbeddingRepository(
        database: database,
        onReplacementCheckpoint: (checkpoint) {
          if (checkpoint == EmbeddingReplacementCheckpoint.indexSetInserted) {
            throw StateError('injected replacement failure');
          }
        },
      );

      await expectLater(
        failing.replaceIndexSet(
          _generation(
            id: 'set-new',
            fields: const <SearchSourceField>[SearchSourceField.secretNote],
          ),
        ),
        throwsStateError,
      );

      final restored = await repository.getIndexSetBySource(
        const SearchSourceKey.secret('secret-1'),
        'model-1',
      );
      expect(restored?.id, 'set-old');
      expect(
        restored?.chunks.single.sourceField,
        SearchSourceField.secretTitle,
      );
    },
  );

  test(
    'write guard invalidation during replacement rolls back the old generation',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database);
      final repository = SqliteEmbeddingRepository(database: database);
      await repository.replaceIndexSet(
        _generation(
          id: 'set-old',
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );
      var valid = true;
      final guarded = SqliteEmbeddingRepository(
        database: database,
        onReplacementCheckpoint: (checkpoint) {
          if (checkpoint == EmbeddingReplacementCheckpoint.indexSetInserted) {
            valid = false;
          }
        },
      );

      await expectLater(
        guarded.replaceIndexSetGuarded(
          _generation(
            id: 'set-new',
            fields: const <SearchSourceField>[SearchSourceField.secretNote],
          ),
          validate: () {
            if (!valid) {
              throw const EmbeddingIndexStaleWriteException();
            }
          },
        ),
        throwsA(isA<EmbeddingIndexStaleWriteException>()),
      );

      final restored = await repository.getIndexSetBySource(
        const SearchSourceKey.secret('secret-1'),
        'model-1',
      );
      expect(restored?.id, 'set-old');
      expect(
        restored?.chunks.single.sourceField,
        SearchSourceField.secretTitle,
      );
    },
  );

  test(
    'zero chunk set is persisted and identical replacement is a no-op',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database);
      final repository = SqliteEmbeddingRepository(database: database);
      final empty = _generation(
        id: 'set-empty',
        fields: const <SearchSourceField>[],
      );

      expect(await repository.replaceIndexSet(empty), isTrue);
      expect(await repository.replaceIndexSet(empty), isFalse);

      final restored = await repository.getIndexSetBySource(
        const SearchSourceKey.secret('secret-1'),
        'model-1',
      );
      expect(restored?.vectorDimension, 0);
      expect(restored?.chunks, isEmpty);
    },
  );

  test(
    'source timestamp drift rejects replacement before deleting old set',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database);
      final repository = SqliteEmbeddingRepository(database: database);
      await repository.replaceIndexSet(
        _generation(
          id: 'set-old',
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );
      await database.run(
        (db) => db.update(
          'secret_items',
          const <String, Object?>{'updated_at': 2},
          where: 'id = ?',
          whereArgs: const <Object>['secret-1'],
        ),
      );

      await expectLater(
        repository.replaceIndexSet(
          _generation(
            id: 'set-new',
            fields: const <SearchSourceField>[SearchSourceField.secretNote],
          ),
        ),
        throwsA(isA<EmbeddingIndexStaleWriteException>()),
      );
    },
  );

  test('replacement removes stale generations from other models', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    await _insertOwners(database);
    await database.run(
      (db) => db.insert(
        'model_registry',
        trustedModelRegistryRow(id: 'model-2', name: 'Embedding 2'),
      ),
    );
    final repository = SqliteEmbeddingRepository(database: database);
    await repository.replaceIndexSet(
      _generation(
        id: 'set-model-1',
        fields: const <SearchSourceField>[SearchSourceField.secretTitle],
      ),
    );

    await repository.replaceIndexSet(
      _generation(
        id: 'set-model-2',
        modelId: 'model-2',
        fields: const <SearchSourceField>[SearchSourceField.secretTitle],
      ),
    );

    expect(
      await repository.getIndexSetBySource(
        const SearchSourceKey.secret('secret-1'),
        'model-1',
      ),
      isNull,
    );
    expect(
      await repository.getIndexSetBySource(
        const SearchSourceKey.secret('secret-1'),
        'model-2',
      ),
      isNotNull,
    );
  });

  test(
    'compatible reader filters generation metadata and loads chunks',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database);
      final repository = SqliteEmbeddingRepository(database: database);
      await repository.replaceIndexSet(
        _generation(
          id: 'set-compatible',
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );

      final compatible = await repository.getCompatibleIndexSets(
        _compatibility(),
        limit: 100,
      );
      final wrongKey = await repository.getCompatibleIndexSets(
        _compatibility(fingerprintKeyId: 'other-key'),
        limit: 100,
      );

      expect(compatible, hasLength(1));
      expect(compatible.single.id, 'set-compatible');
      expect(compatible.single.chunks, hasLength(1));
      expect(wrongKey, isEmpty);
    },
  );

  test(
    'compatible reader isolates and purges one structurally corrupt generation',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database);
      final repository = SqliteEmbeddingRepository(database: database);
      await repository.replaceIndexSet(
        _generation(
          id: 'set-corrupt',
          sourceId: 'secret-1',
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );
      await repository.replaceIndexSet(
        _generation(
          id: 'set-valid',
          sourceId: 'secret-2',
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );
      await database.run(
        (db) => db.update(
          DatabaseSchema.embeddingIndexSets,
          const <String, Object?>{'chunk_count': 2},
          where: 'id = ?',
          whereArgs: const <Object>['set-corrupt'],
        ),
      );

      final compatible = await repository.getCompatibleIndexSets(
        _compatibility(),
        limit: 100,
      );

      expect(compatible.map((set) => set.id), const <String>['set-valid']);
      expect(
        await database.run(
          (db) => db.query(
            DatabaseSchema.embeddingIndexSets,
            columns: const <String>['id'],
            orderBy: 'id ASC',
          ),
        ),
        const <Map<String, Object?>>[
          <String, Object?>{'id': 'set-valid'},
        ],
      );
    },
  );
}
