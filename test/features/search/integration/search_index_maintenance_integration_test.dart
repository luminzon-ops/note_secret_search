import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test(
    'index status purges globally incompatible generations before rebuild',
    () async {
      final database = await openTestAppDatabase();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'key-current',
            searchIndexFingerprintKey: Uint8List(32),
          ),
        );
      addTearDown(() async {
        keyStore.clear();
        await database.close();
      });
      await _insertOwners(database);

      final repository = SqliteEmbeddingRepository(database: database);
      final configuration = SearchConfiguration.defaults();
      await repository.replaceIndexSet(
        _generation(
          id: 'set-default-stale-config',
          sourceId: 'secret-default-stale',
          vaultId: 'default',
          configuration: configuration,
          indexConfigEpoch: configuration.configurationEpoch + 1,
        ),
      );
      await repository.replaceIndexSet(
        _generation(
          id: 'set-other-stale-model',
          sourceId: 'secret-other-stale',
          vaultId: 'vault-2',
          configuration: configuration,
          modelRevisionHash: 'b' * 64,
        ),
      );
      await repository.replaceIndexSet(
        _generation(
          id: 'set-other-compatible',
          sourceId: 'secret-other-compatible',
          vaultId: 'vault-2',
          configuration: configuration,
        ),
      );

      final service = SearchIndexService(
        repository: repository,
        cryptoService: const _EmptyCryptoService(),
        embeddingEngine: const _ReadyEmbeddingEngine(),
        sessionKeyStore: keyStore,
      );
      await service.buildCorpusStatus(
        activeVaultId: 'default',
        corpus: SearchCorpusReader(
          secretRepository: SqliteSecretRepository(database: database),
          noteRepository: SqliteNoteRepository(database: database),
        ),
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
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
          <String, Object?>{'id': 'set-other-compatible'},
        ],
      );
    },
  );

  test('index status purges all generations when no model is active', () async {
    final database = await openTestAppDatabase();
    final keyStore = DatabaseSessionKeyStore()
      ..replace(
        DatabaseSessionKeys(
          databaseKey: Uint8List(32),
          fieldKey: Uint8List(32),
          keyId: 'key-current',
          searchIndexFingerprintKey: Uint8List(32),
        ),
      );
    addTearDown(() async {
      keyStore.clear();
      await database.close();
    });
    await _insertOwners(database);

    final repository = SqliteEmbeddingRepository(database: database);
    final configuration = SearchConfiguration.defaults();
    await repository.replaceIndexSet(
      _generation(
        id: 'set-to-purge',
        sourceId: 'secret-default-stale',
        vaultId: 'default',
        configuration: configuration,
      ),
    );

    final service = SearchIndexService(
      repository: repository,
      cryptoService: const _EmptyCryptoService(),
      embeddingEngine: const _ReadyEmbeddingEngine(),
      sessionKeyStore: keyStore,
    );
    await service.buildCorpusStatus(
      activeVaultId: 'default',
      corpus: SearchCorpusReader(
        secretRepository: SqliteSecretRepository(database: database),
        noteRepository: SqliteNoteRepository(database: database),
      ),
      activeEmbeddingModel: null,
      modelRevisionHash: '',
      configuration: configuration,
    );

    expect(
      await database.run((db) => db.query(DatabaseSchema.embeddingIndexSets)),
      isEmpty,
    );
  });
}

Future<void> _insertOwners(TestAppDatabase database) {
  return database.run((db) async {
    await db.insert(DatabaseSchema.vaults, <String, Object?>{
      'id': 'vault-2',
      'name': 'Second vault',
      'is_default': 0,
      'encryption_version': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    for (final row in const <Map<String, Object?>>[
      <String, Object?>{
        'id': 'secret-default-stale',
        'vault_id': 'default',
        'title': 'Default stale',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      },
      <String, Object?>{
        'id': 'secret-other-stale',
        'vault_id': 'vault-2',
        'title': 'Other stale',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      },
      <String, Object?>{
        'id': 'secret-other-compatible',
        'vault_id': 'vault-2',
        'title': 'Other compatible',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      },
    ]) {
      await db.insert(DatabaseSchema.secretItems, row);
    }
    await db.insert(
      DatabaseSchema.modelRegistry,
      trustedModelRegistryRow(
        id: _model.id,
        type: _model.type,
        provider: _model.provider,
        name: _model.name,
        version: _model.version,
        quantization: _model.quantization,
        checksum: _model.checksum,
      ),
    );
  });
}

EmbeddingIndexSet _generation({
  required String id,
  required String sourceId,
  required String vaultId,
  required SearchConfiguration configuration,
  String modelRevisionHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int? indexConfigEpoch,
}) {
  return EmbeddingIndexSet(
    id: id,
    sourceKey: SearchSourceKey.secret(sourceId),
    vaultId: vaultId,
    modelId: _model.id,
    modelRevisionHash: modelRevisionHash,
    sourceUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1),
    sourceFingerprint: Uint8List(32),
    fingerprintKeyId: 'key-current',
    fingerprintVersion: 1,
    indexConfigVersion: searchIndexConfigurationVersion,
    indexConfigEpoch: indexConfigEpoch ?? configuration.configurationEpoch,
    indexConfigHash: searchIndexConfigurationHash(configuration),
    chunkSchemaVersion: 1,
    vectorFormatVersion: 1,
    vectorDimension: 0,
    chunks: const [],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  );
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

class _ReadyEmbeddingEngine implements EmbeddingEngine {
  const _ReadyEmbeddingEngine();

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
