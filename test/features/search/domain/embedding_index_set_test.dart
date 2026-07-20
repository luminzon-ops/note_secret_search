import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';

void main() {
  test('source field identity has stable wire names and source ownership', () {
    expect(
      SearchSourceField.values.map((field) => field.wireName),
      const <String>[
        'secret.title',
        'secret.username',
        'secret.password',
        'secret.website_url',
        'secret.note',
        'secret.tags',
        'note.title',
        'note.summary',
        'note.body',
        'note.tags',
      ],
    );
    expect(SearchSourceField.secretPassword.supportsSemanticIndex, isFalse);
    expect(SearchSourceField.parse('note.body'), SearchSourceField.noteBody);
    expect(
      () => SearchSourceField.parse('note.unknown'),
      throwsFormatException,
    );
  });

  test('generation derives chunk count and preserves field-local identity', () {
    final generation = _generation(
      chunks: <EmbeddingChunk>[
        _chunk(
          id: 'chunk-title',
          field: SearchSourceField.secretTitle,
          fieldChunkIndex: 0,
        ),
        _chunk(
          id: 'chunk-note',
          field: SearchSourceField.secretNote,
          fieldChunkIndex: 0,
        ),
      ],
    );

    expect(generation.sourceKey, const SearchSourceKey.secret('secret-1'));
    expect(generation.chunkCount, 2);
    expect(generation.vectorDimension, 2);
    expect(generation.chunks.map((chunk) => chunk.fieldChunkIndex), const <int>[
      0,
      0,
    ]);
  });

  test('generation rejects cross-source fields and malformed vector blobs', () {
    expect(
      () => _generation(
        chunks: <EmbeddingChunk>[
          _chunk(
            id: 'wrong-source',
            field: SearchSourceField.noteBody,
            fieldChunkIndex: 0,
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => _generation(
        chunks: <EmbeddingChunk>[
          _chunk(
            id: 'wrong-size',
            field: SearchSourceField.secretTitle,
            fieldChunkIndex: 0,
            vectorBlob: Uint8List(4),
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => _generation(
        chunks: <EmbeddingChunk>[
          _chunk(
            id: 'password',
            field: SearchSourceField.secretPassword,
            fieldChunkIndex: 0,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('zero chunk generation requires zero vector dimension', () {
    final empty = _generation(chunks: const <EmbeddingChunk>[], dimension: 0);
    expect(empty.chunkCount, 0);

    expect(
      () => _generation(chunks: const <EmbeddingChunk>[], dimension: 2),
      throwsArgumentError,
    );
  });
}

EmbeddingIndexSet _generation({
  required List<EmbeddingChunk> chunks,
  int dimension = 2,
}) {
  return EmbeddingIndexSet(
    id: 'set-1',
    sourceKey: const SearchSourceKey.secret('secret-1'),
    vaultId: 'vault-1',
    modelId: 'model-1',
    modelRevisionHash: 'a' * 64,
    sourceUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
    sourceFingerprint: Uint8List(32),
    fingerprintKeyId: 'key-1',
    fingerprintVersion: 1,
    indexConfigVersion: 1,
    indexConfigEpoch: 0,
    indexConfigHash: 'b' * 64,
    chunkSchemaVersion: 1,
    vectorFormatVersion: 1,
    vectorDimension: dimension,
    chunks: chunks,
    createdAt: DateTime.fromMillisecondsSinceEpoch(2),
  );
}

EmbeddingChunk _chunk({
  required String id,
  required SearchSourceField field,
  required int fieldChunkIndex,
  Uint8List? vectorBlob,
}) {
  return EmbeddingChunk(
    id: id,
    indexSetId: 'set-1',
    sourceField: field,
    fieldChunkIndex: fieldChunkIndex,
    chunkFingerprint: Uint8List(32),
    vectorBlob: vectorBlob ?? Uint8List(8),
    tokenCount: 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(2),
  );
}
