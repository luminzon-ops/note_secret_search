import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test(
    'header reader preserves typed source identity and exact model scope',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      await _insertOwners(database);
      final repository = SqliteEmbeddingRepository(database: database);
      await repository.replaceIndexSet(
        _generation(
          id: 'secret-set',
          sourceKey: const SearchSourceKey.secret('shared'),
          field: SearchSourceField.secretTitle,
        ),
      );
      await repository.replaceIndexSet(
        _generation(
          id: 'note-set',
          sourceKey: const SearchSourceKey.note('shared'),
          field: SearchSourceField.noteTitle,
        ),
      );

      final headers = await repository
          .getIndexSetHeadersBySources(const <SearchSourceKey>[
            SearchSourceKey.note('shared'),
            SearchSourceKey.secret('missing'),
            SearchSourceKey.secret('shared'),
          ], 'model-1');
      final otherModel = await repository.getIndexSetHeadersBySources(
        const <SearchSourceKey>[
          SearchSourceKey.secret('shared'),
          SearchSourceKey.note('shared'),
        ],
        'model-2',
      );

      expect(
        headers.keys,
        unorderedEquals(<SearchSourceKey>[
          const SearchSourceKey.secret('shared'),
          const SearchSourceKey.note('shared'),
        ]),
      );
      expect(headers[const SearchSourceKey.secret('shared')]?.id, 'secret-set');
      expect(headers[const SearchSourceKey.note('shared')]?.id, 'note-set');
      expect(headers.values.every((header) => header.chunkCount == 1), isTrue);
      expect(
        headers.values.every((header) => header.vectorDimension == 2),
        isTrue,
      );
      expect(otherModel, isEmpty);
    },
  );

  test(
    'header reader rejects batches above the 200 source bind budget',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      final repository = SqliteEmbeddingRepository(database: database);

      await expectLater(
        Future<void>.sync(() async {
          await repository.getIndexSetHeadersBySources(<SearchSourceKey>[
            for (var index = 0; index <= embeddingIndexHeaderBatchSize; index++)
              SearchSourceKey.secret('secret-$index'),
          ], 'model-1');
        }),
        throwsArgumentError,
      );
    },
  );
}

Future<void> _insertOwners(TestAppDatabase database) {
  return database.run((db) async {
    await db.insert('secret_items', <String, Object?>{
      'id': 'shared',
      'vault_id': 'default',
      'title': 'Secret',
      'favorite': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('note_items', <String, Object?>{
      'id': 'shared',
      'vault_id': 'default',
      'title': 'Note',
      'content_ciphertext': Uint8List.fromList(const <int>[1]),
      'favorite': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert(
      'model_registry',
      trustedModelRegistryRow(id: 'model-1'),
    );
  });
}

EmbeddingIndexSet _generation({
  required String id,
  required SearchSourceKey sourceKey,
  required SearchSourceField field,
}) {
  return EmbeddingIndexSet(
    id: id,
    sourceKey: sourceKey,
    vaultId: 'default',
    modelId: 'model-1',
    modelRevisionHash: 'a' * 64,
    sourceUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
    sourceFingerprint: Uint8List(32),
    fingerprintKeyId: 'key-1',
    fingerprintVersion: 1,
    indexConfigVersion: 1,
    indexConfigEpoch: 1,
    indexConfigHash: 'b' * 64,
    chunkSchemaVersion: 1,
    vectorFormatVersion: 1,
    vectorDimension: 2,
    chunks: <EmbeddingChunk>[
      EmbeddingChunk(
        id: '$id-chunk',
        indexSetId: id,
        sourceField: field,
        fieldChunkIndex: 0,
        chunkFingerprint: Uint8List(32),
        vectorBlob: Float32VectorCodec.encode(const <double>[1, 0]),
        tokenCount: 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    ],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  );
}
