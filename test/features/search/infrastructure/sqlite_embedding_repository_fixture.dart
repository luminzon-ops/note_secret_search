part of 'sqlite_embedding_repository_test.dart';

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
    await db.insert('model_registry', trustedModelRegistryRow(id: 'model-1'));
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
