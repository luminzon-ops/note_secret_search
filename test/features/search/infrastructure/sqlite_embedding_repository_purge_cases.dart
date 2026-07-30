part of 'sqlite_embedding_repository_test.dart';

void _runSqliteEmbeddingPurgeCases() {
  test('stale purge deletes at most one bounded batch', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    await _insertOwners(database);
    final repository = SqliteEmbeddingRepository(database: database);
    await repository.replaceIndexSet(
      _generation(
        id: 'set-stale',
        indexConfigEpoch: 1,
        fields: const <SearchSourceField>[SearchSourceField.secretTitle],
      ),
    );

    expect(
      await repository.purgeIncompatibleIndexSets(
        _compatibility(indexConfigEpoch: 2),
        batchSize: 100,
      ),
      1,
    );
    expect(
      await repository.purgeIncompatibleIndexSets(
        _compatibility(indexConfigEpoch: 2),
        batchSize: 100,
      ),
      0,
    );
  });

  test(
    'stale purge preserves compatible other Vault sets and removes stale ones',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database, includeSecondVault: true);
      final repository = SqliteEmbeddingRepository(database: database);
      await repository.replaceIndexSet(
        _generation(
          id: 'set-default-stale',
          indexConfigEpoch: 2,
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );
      await repository.replaceIndexSet(
        _generation(
          id: 'set-other-vault-compatible',
          sourceId: 'secret-vault-2',
          vaultId: 'vault-2',
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );
      await database.run(
        (db) => db.insert('secret_items', <String, Object?>{
          'id': 'secret-vault-2-stale',
          'vault_id': 'vault-2',
          'title': 'Second vault stale secret',
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
        }),
      );
      await repository.replaceIndexSet(
        _generation(
          id: 'set-other-vault-stale',
          sourceId: 'secret-vault-2-stale',
          vaultId: 'vault-2',
          indexConfigEpoch: 2,
          fields: const <SearchSourceField>[SearchSourceField.secretTitle],
        ),
      );

      expect(
        await repository.purgeIncompatibleIndexSets(
          _compatibility(indexConfigEpoch: 1),
          batchSize: 100,
        ),
        2,
      );
      expect(
        await database.run(
          (db) => db.query(
            DatabaseSchema.embeddingIndexSets,
            columns: const <String>['id'],
            orderBy: 'id ASC',
          ),
        ),
        const <Map<String, Object?>>[
          <String, Object?>{'id': 'set-other-vault-compatible'},
        ],
      );
    },
  );

  test('full purge deletes derived index data in bounded batches', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    await _insertOwners(database);
    final repository = SqliteEmbeddingRepository(database: database);
    await repository.replaceIndexSet(
      _generation(
        id: 'set-to-purge',
        fields: const <SearchSourceField>[SearchSourceField.secretTitle],
      ),
    );

    expect(await repository.purgeAllIndexSets(batchSize: 1), 1);
    expect(await repository.purgeAllIndexSets(batchSize: 1), 0);
  });
}
