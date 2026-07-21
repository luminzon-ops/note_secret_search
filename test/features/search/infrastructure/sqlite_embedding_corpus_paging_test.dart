import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test('corrupt-only page advances without scanning the valid tail', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    await _insertCorruptPrefixAndValidTail(database);
    final repository = SqliteEmbeddingRepository(database: database);

    final first = await repository.getCompatibleIndexSetPage(
      _compatibility(),
      limit: 100,
    );

    expect(first.sets, isEmpty);
    expect(first.nextAfterId, 'set-099');
    expect(first.reachedEnd, isFalse);

    final second = await repository.getCompatibleIndexSetPage(
      _compatibility(),
      afterId: first.nextAfterId,
      limit: 100,
    );
    expect(second.sets.map((set) => set.id), const <String>['set-100']);
    expect(second.nextAfterId, 'set-100');
    expect(second.reachedEnd, isTrue);
  });

  test(
    'semantic search advances past a corrupt-only production page',
    () async {
      final database = await openTestAppDatabase();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'key-1',
            searchIndexFingerprintKey: Uint8List(32),
          ),
        );
      addTearDown(() async {
        keyStore.clear();
        await database.close();
      });
      final configuration = SearchConfiguration.defaults();
      await _insertCorruptPrefixAndValidTail(
        database,
        indexConfigHash: searchIndexConfigurationHash(configuration),
        indexConfigEpoch: configuration.configurationEpoch,
      );

      final results =
          await SemanticSearchService(
            repository: SqliteEmbeddingRepository(database: database),
            embeddingEngine: const _UnitEmbeddingEngine(),
            cryptoService: const _EmptyCryptoService(),
            sessionKeyStore: keyStore,
          ).searchCorpus(
            activeVaultId: 'default',
            query: 'query',
            configuration: configuration,
            modelRevisionHash: 'a' * 64,
            activeEmbeddingModel: _model,
            corpus: SearchCorpusReader(
              secretRepository: SqliteSecretRepository(database: database),
              noteRepository: SqliteNoteRepository(database: database),
            ),
          );

      expect(results.map((result) => result.item.id), const <String>[
        'secret-100',
      ]);
    },
  );

  test(
    'semantic search completes after an exact full production page',
    () async {
      final database = await openTestAppDatabase();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'key-1',
            searchIndexFingerprintKey: Uint8List(32),
          ),
        );
      addTearDown(() async {
        keyStore.clear();
        await database.close();
      });
      final configuration = SearchConfiguration.defaults();
      await _insertValidPage(
        database,
        indexConfigHash: searchIndexConfigurationHash(configuration),
        indexConfigEpoch: configuration.configurationEpoch,
      );

      final results =
          await SemanticSearchService(
            repository: SqliteEmbeddingRepository(database: database),
            embeddingEngine: const _UnitEmbeddingEngine(),
            cryptoService: const _EmptyCryptoService(),
            sessionKeyStore: keyStore,
          ).searchCorpus(
            activeVaultId: 'default',
            query: 'query',
            configuration: configuration,
            modelRevisionHash: 'a' * 64,
            activeEmbeddingModel: _model,
            corpus: SearchCorpusReader(
              secretRepository: SqliteSecretRepository(database: database),
              noteRepository: SqliteNoteRepository(database: database),
            ),
          );

      expect(results, hasLength(100));
    },
  );
}

Future<void> _insertCorruptPrefixAndValidTail(
  TestAppDatabase database, {
  String indexConfigHash =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  int indexConfigEpoch = 1,
}) {
  return database.transaction<void>((executor) async {
    await executor.insert(DatabaseSchema.modelRegistry, <String, Object?>{
      'id': 'model-1',
      'type': 'embedding',
      'provider': 'local',
      'name': 'Embedding',
      'integrity_status': 'valid',
      'enabled': 1,
    });
    for (var index = 0; index <= 100; index++) {
      final suffix = index.toString().padLeft(3, '0');
      final sourceId = 'secret-$suffix';
      final setId = 'set-$suffix';
      await executor.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': sourceId,
        'vault_id': 'default',
        'title': 'Secret $suffix',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await executor
          .insert(DatabaseSchema.embeddingIndexSets, <String, Object?>{
            'id': setId,
            'source_type': 'secret',
            'source_id': sourceId,
            'vault_id': 'default',
            'model_id': 'model-1',
            'model_revision_hash': 'a' * 64,
            'source_updated_at': 1,
            'source_fingerprint': Uint8List(32),
            'fingerprint_key_id': 'key-1',
            'fingerprint_version': 1,
            'index_config_version': 1,
            'index_config_epoch': indexConfigEpoch,
            'index_config_hash': indexConfigHash,
            'chunk_schema_version': 1,
            'vector_format_version': 1,
            'vector_dimension': 2,
            'chunk_count': index < 100 ? 2 : 1,
            'created_at': 1,
          });
      await executor.insert(DatabaseSchema.embeddingChunks, <String, Object?>{
        'id': 'chunk-$suffix',
        'index_set_id': setId,
        'source_field': 'secret.title',
        'field_chunk_index': 0,
        'chunk_fingerprint': Uint8List(32),
        'vector_blob': Float32VectorCodec.encode(const <double>[1, 0]),
        'token_count': 1,
        'created_at': 1,
      });
    }
  });
}

Future<void> _insertValidPage(
  TestAppDatabase database, {
  required String indexConfigHash,
  required int indexConfigEpoch,
}) {
  return database.transaction<void>((executor) async {
    await executor.insert(DatabaseSchema.modelRegistry, <String, Object?>{
      'id': 'model-1',
      'type': 'embedding',
      'provider': 'local',
      'name': 'Embedding',
      'integrity_status': 'valid',
      'enabled': 1,
    });
    for (var index = 0; index < 100; index++) {
      final suffix = index.toString().padLeft(3, '0');
      final sourceId = 'secret-$suffix';
      final setId = 'set-$suffix';
      await executor.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': sourceId,
        'vault_id': 'default',
        'title': 'Secret $suffix',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await executor
          .insert(DatabaseSchema.embeddingIndexSets, <String, Object?>{
            'id': setId,
            'source_type': 'secret',
            'source_id': sourceId,
            'vault_id': 'default',
            'model_id': 'model-1',
            'model_revision_hash': 'a' * 64,
            'source_updated_at': 1,
            'source_fingerprint': Uint8List(32),
            'fingerprint_key_id': 'key-1',
            'fingerprint_version': 1,
            'index_config_version': 1,
            'index_config_epoch': indexConfigEpoch,
            'index_config_hash': indexConfigHash,
            'chunk_schema_version': 1,
            'vector_format_version': 1,
            'vector_dimension': 2,
            'chunk_count': 1,
            'created_at': 1,
          });
      await executor.insert(DatabaseSchema.embeddingChunks, <String, Object?>{
        'id': 'chunk-$suffix',
        'index_set_id': setId,
        'source_field': 'secret.title',
        'field_chunk_index': 0,
        'chunk_fingerprint': Uint8List(32),
        'vector_blob': Float32VectorCodec.encode(const <double>[1, 0]),
        'token_count': 1,
        'created_at': 1,
      });
    }
  });
}

EmbeddingIndexCompatibility _compatibility() {
  return const EmbeddingIndexCompatibility(
    vaultId: 'default',
    modelId: 'model-1',
    modelRevisionHash:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    fingerprintKeyId: 'key-1',
    fingerprintVersion: 1,
    indexConfigVersion: 1,
    indexConfigEpoch: 1,
    indexConfigHash:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    chunkSchemaVersion: 1,
    vectorFormatVersion: 1,
  );
}

class _UnitEmbeddingEngine implements EmbeddingEngine {
  const _UnitEmbeddingEngine();

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    return const EmbeddingVector(values: <double>[1, 0], tokenCount: 1);
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: 'ready',
      status: EmbeddingRuntimeStatus.ready,
      vectorDimension: 2,
    );
  }
}

class _EmptyCryptoService implements CryptoService {
  const _EmptyCryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return '';
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    throw UnimplementedError();
  }
}

const _model = ModelRegistryEntry(
  id: 'model-1',
  type: 'embedding',
  provider: 'local',
  name: 'Embedding',
  version: '1',
  sizeBytes: 1,
  quantization: 'fp32',
  minRamMb: 1,
  recommendedTier: 'test',
  localPath: 'model.onnx',
  checksum: 'checksum',
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
);
