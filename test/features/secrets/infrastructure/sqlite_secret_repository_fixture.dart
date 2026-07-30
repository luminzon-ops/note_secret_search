part of 'sqlite_secret_repository_test.dart';

SecretItem _legacySecret() {
  return SecretItem(
    id: 'legacy-secret',
    vaultId: 'vault-1',
    title: 'Legacy',
    usernameCiphertext: _legacyBytes('legacy-user'),
    passwordCiphertext: _legacyBytes('legacy-password'),
    websiteUrlCiphertext: null,
    noteCiphertext: null,
    tags: const [],
    categoryId: null,
    favorite: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );
}

Uint8List _legacyBytes(String value) => Uint8List.fromList(value.codeUnits);

Future<void> _insertTestVault(TestAppDatabase database) {
  return database.run(
    (db) => db.insert(DatabaseSchema.vaults, <String, Object?>{
      'id': 'vault-1',
      'name': 'Test Vault',
      'is_default': 0,
      'encryption_version': 1,
      'created_at': 1,
      'updated_at': 1,
    }),
  );
}

Future<void> _insertEmbedding(
  TestAppDatabase database,
  String sourceId,
  String sourceType,
) {
  return database.run((db) async {
    await db.insert(
      DatabaseSchema.modelRegistry,
      trustedModelRegistryRow(
        id: 'model-1',
        name: 'Test model',
        enabled: false,
      ),
    );
    await db.insert(DatabaseSchema.embeddingIndexSets, <String, Object?>{
      'id': 'embedding-set-1',
      'source_type': sourceType,
      'source_id': sourceId,
      'vault_id': 'vault-1',
      'model_id': 'model-1',
      'model_revision_hash': 'a' * 64,
      'source_updated_at': 1,
      'source_fingerprint': Uint8List(32),
      'fingerprint_key_id': 'test-key',
      'fingerprint_version': 1,
      'index_config_version': 1,
      'index_config_epoch': 1,
      'index_config_hash': 'b' * 64,
      'chunk_schema_version': 1,
      'vector_format_version': 1,
      'vector_dimension': 1,
      'chunk_count': 1,
      'created_at': 1,
    });
    await db.insert(DatabaseSchema.embeddingChunks, <String, Object?>{
      'id': 'embedding-1',
      'index_set_id': 'embedding-set-1',
      'source_field': 'secret.title',
      'field_chunk_index': 0,
      'chunk_fingerprint': Uint8List(32),
      'vector_blob': Uint8List(4),
      'token_count': 1,
      'created_at': 1,
    });
  });
}

class _FailingItemTagStore implements ItemTagStore {
  const _FailingItemTagStore({
    this.failReplace = false,
    this.failUnlink = false,
  });

  final bool failReplace;
  final bool failUnlink;

  @override
  Future<Map<String, List<String>>> loadTagsByItemIds(
    DatabaseExecutor executor, {
    required List<String> itemIds,
    required ItemTagType itemType,
    required String vaultId,
  }) async {
    return const <String, List<String>>{};
  }

  @override
  Future<void> replaceTags(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
    required List<String> tags,
  }) {
    if (failReplace) {
      throw StateError('injected_tag_failure');
    }
    return Future<void>.value();
  }

  @override
  Future<void> unlinkItem(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
  }) {
    if (failUnlink) {
      throw StateError('injected_tag_failure');
    }
    return Future<void>.value();
  }
}
