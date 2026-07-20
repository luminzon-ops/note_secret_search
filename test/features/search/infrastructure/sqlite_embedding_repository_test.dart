import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
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
      (db) => db.insert('model_registry', <String, Object?>{
        'id': 'model-2',
        'type': 'embedding',
        'provider': 'local',
        'name': 'Embedding 2',
        'integrity_status': 'valid',
        'enabled': 1,
      }),
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

  test('stale purge is scoped to the compatibility vault', () async {
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
        id: 'set-other-vault',
        sourceId: 'secret-vault-2',
        vaultId: 'vault-2',
        fields: const <SearchSourceField>[SearchSourceField.secretTitle],
      ),
    );

    expect(
      await repository.purgeIncompatibleIndexSets(
        _compatibility(indexConfigEpoch: 1),
        batchSize: 100,
      ),
      1,
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
        <String, Object?>{'id': 'set-other-vault'},
      ],
    );
  });

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

Future<void> _insertOwners(
  TestAppDatabase database, {
  bool includeSecondVault = false,
}) {
  return database.run((db) async {
    if (includeSecondVault) {
      await db.insert('vaults', <String, Object?>{
        'id': 'vault-2',
        'name': 'Second vault',
        'description': null,
        'is_default': 0,
        'encryption_version': 1,
        'created_at': 1,
        'updated_at': 1,
      });
    }
    await db.insert('secret_items', <String, Object?>{
      'id': 'secret-1',
      'vault_id': 'default',
      'title': 'Secret',
      'favorite': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    if (includeSecondVault) {
      await db.insert('secret_items', <String, Object?>{
        'id': 'secret-vault-2',
        'vault_id': 'vault-2',
        'title': 'Second vault secret',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
    }
    await db.insert('secret_items', <String, Object?>{
      'id': 'secret-2',
      'vault_id': 'default',
      'title': 'Second secret',
      'favorite': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('model_registry', <String, Object?>{
      'id': 'model-1',
      'type': 'embedding',
      'provider': 'local',
      'name': 'Embedding',
      'integrity_status': 'valid',
      'enabled': 1,
    });
  });
}

EmbeddingIndexSet _generation({
  required String id,
  String sourceId = 'secret-1',
  String modelId = 'model-1',
  String vaultId = 'default',
  int indexConfigEpoch = 1,
  required List<SearchSourceField> fields,
}) {
  final dimension = fields.isEmpty ? 0 : 2;
  return EmbeddingIndexSet(
    id: id,
    sourceKey: SearchSourceKey.secret(sourceId),
    vaultId: vaultId,
    modelId: modelId,
    modelRevisionHash: 'a' * 64,
    sourceUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
    sourceFingerprint: Uint8List(32),
    fingerprintKeyId: 'key-1',
    fingerprintVersion: 1,
    indexConfigVersion: 1,
    indexConfigEpoch: indexConfigEpoch,
    indexConfigHash: 'b' * 64,
    chunkSchemaVersion: 1,
    vectorFormatVersion: 1,
    vectorDimension: dimension,
    chunks: <EmbeddingChunk>[
      for (var index = 0; index < fields.length; index++)
        EmbeddingChunk(
          id: '$id-chunk-$index',
          indexSetId: id,
          sourceField: fields[index],
          fieldChunkIndex: 0,
          chunkFingerprint: Uint8List.fromList(List<int>.filled(32, index + 1)),
          vectorBlob: Float32VectorCodec.encode(<double>[
            1 - index * 0.25,
            index * 0.25,
          ]),
          tokenCount: 1,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
    ],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  );
}

EmbeddingIndexCompatibility _compatibility({
  String fingerprintKeyId = 'key-1',
  int indexConfigEpoch = 1,
}) {
  return EmbeddingIndexCompatibility(
    vaultId: 'default',
    modelId: 'model-1',
    modelRevisionHash: 'a' * 64,
    fingerprintKeyId: fingerprintKeyId,
    fingerprintVersion: 1,
    indexConfigVersion: 1,
    indexConfigEpoch: indexConfigEpoch,
    indexConfigHash: 'b' * 64,
    chunkSchemaVersion: 1,
    vectorFormatVersion: 1,
  );
}
