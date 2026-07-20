import 'dart:typed_data';

import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';

class EmbeddingIndexSet {
  EmbeddingIndexSet({
    required this.id,
    required this.sourceKey,
    required this.vaultId,
    required this.modelId,
    required this.modelRevisionHash,
    required this.sourceUpdatedAt,
    required List<int> sourceFingerprint,
    required this.fingerprintKeyId,
    required this.fingerprintVersion,
    required this.indexConfigVersion,
    required this.indexConfigEpoch,
    required this.indexConfigHash,
    required this.chunkSchemaVersion,
    required this.vectorFormatVersion,
    required this.vectorDimension,
    required List<EmbeddingChunk> chunks,
    required this.createdAt,
  }) : sourceFingerprint = Uint8List.fromList(sourceFingerprint),
       chunks = List<EmbeddingChunk>.unmodifiable(chunks) {
    _validate();
  }

  final String id;
  final SearchSourceKey sourceKey;
  final String vaultId;
  final String modelId;
  final String modelRevisionHash;
  final DateTime sourceUpdatedAt;
  final Uint8List sourceFingerprint;
  final String fingerprintKeyId;
  final int fingerprintVersion;
  final int indexConfigVersion;
  final int indexConfigEpoch;
  final String indexConfigHash;
  final int chunkSchemaVersion;
  final int vectorFormatVersion;
  final int vectorDimension;
  final List<EmbeddingChunk> chunks;
  final DateTime createdAt;

  int get chunkCount => chunks.length;

  void _validate() {
    if (id.isEmpty ||
        sourceKey.id.isEmpty ||
        vaultId.isEmpty ||
        modelId.isEmpty ||
        fingerprintKeyId.isEmpty) {
      throw ArgumentError('Embedding index identifiers must not be empty.');
    }
    if (!_isSha256Hex(modelRevisionHash)) {
      throw ArgumentError.value(
        modelRevisionHash,
        'modelRevisionHash',
        'Must be a lowercase SHA-256 hex digest.',
      );
    }
    if (!_isSha256Hex(indexConfigHash)) {
      throw ArgumentError.value(
        indexConfigHash,
        'indexConfigHash',
        'Must be a lowercase SHA-256 hex digest.',
      );
    }
    if (sourceFingerprint.length != 32) {
      throw ArgumentError.value(
        sourceFingerprint.length,
        'sourceFingerprint',
        'Must contain 32 bytes.',
      );
    }
    if (fingerprintVersion < 1 ||
        indexConfigVersion < 1 ||
        indexConfigEpoch < 0 ||
        chunkSchemaVersion < 1 ||
        vectorFormatVersion < 1) {
      throw ArgumentError('Embedding index versions are invalid.');
    }
    if (chunks.isEmpty) {
      if (vectorDimension != 0) {
        throw ArgumentError.value(
          vectorDimension,
          'vectorDimension',
          'A zero-chunk set must use dimension zero.',
        );
      }
      return;
    }
    if (vectorDimension <= 0) {
      throw ArgumentError.value(
        vectorDimension,
        'vectorDimension',
        'A non-empty set requires a positive dimension.',
      );
    }

    final coordinates = <String>{};
    for (final chunk in chunks) {
      if (chunk.indexSetId != id) {
        throw ArgumentError.value(
          chunk.indexSetId,
          'chunks',
          'Chunk belongs to a different index set.',
        );
      }
      if (chunk.sourceField.sourceType != sourceKey.type ||
          !chunk.sourceField.supportsSemanticIndex) {
        throw ArgumentError.value(
          chunk.sourceField.wireName,
          'chunks',
          'Chunk field is not indexable for this source.',
        );
      }
      if (chunk.vectorBlob.length != vectorDimension * 4) {
        throw ArgumentError.value(
          chunk.vectorBlob.length,
          'chunks',
          'Chunk vector length does not match the set dimension.',
        );
      }
      final coordinate =
          '${chunk.sourceField.wireName}:${chunk.fieldChunkIndex}';
      if (!coordinates.add(coordinate)) {
        throw ArgumentError.value(
          coordinate,
          'chunks',
          'Chunk field coordinate must be unique.',
        );
      }
    }
  }
}

bool _isSha256Hex(String value) {
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}
