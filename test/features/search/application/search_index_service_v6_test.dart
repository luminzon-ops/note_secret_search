import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/float32_vector_codec.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

void main() {
  test(
    'index service writes one field-aware float32 generation without password',
    () async {
      final repository = _RecordingEmbeddingIndexRepository();
      final engine = _RecordingEmbeddingEngine();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'root-key-1',
            searchIndexFingerprintKey: Uint8List.fromList(
              List<int>.generate(32, (index) => index),
            ),
          ),
        );
      addTearDown(keyStore.clear);
      final service = SearchIndexService(
        repository: repository,
        cryptoService: _SearchIndexCryptoService(),
        embeddingEngine: engine,
        sessionKeyStore: keyStore,
        clock: () => DateTime.fromMillisecondsSinceEpoch(10),
      );
      final configuration = SearchConfiguration.defaults().copyWith(
        includePasswordField: true,
      );

      final status = await service.buildStatus(
        secrets: <SecretItem>[_secret()],
        notes: const [],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      expect(status.pendingItems, hasLength(1));
      expect(
        status.pendingItems.single.document?.fields.map(
          (content) => content.field,
        ),
        const <SearchSourceField>[
          SearchSourceField.secretTitle,
          SearchSourceField.secretUsername,
          SearchSourceField.secretWebsiteUrl,
          SearchSourceField.secretNote,
          SearchSourceField.secretTags,
        ],
      );

      await service.indexPendingItems(
        items: status.pendingItems,
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      expect(repository.replacements, hasLength(1));
      final generation = repository.replacements.single;
      expect(generation.sourceKey, const SearchSourceKey.secret('secret-1'));
      expect(generation.fingerprintKeyId, 'root-key-1');
      expect(generation.modelRevisionHash, 'a' * 64);
      expect(generation.vectorDimension, 2);
      expect(
        generation.chunks.map((chunk) => chunk.sourceField),
        const <SearchSourceField>[
          SearchSourceField.secretTitle,
          SearchSourceField.secretUsername,
          SearchSourceField.secretWebsiteUrl,
          SearchSourceField.secretNote,
          SearchSourceField.secretTags,
        ],
      );
      expect(
        Float32VectorCodec.decode(
          generation.chunks.first.vectorBlob,
          expectedDimension: 2,
        ).values,
        const <double>[1, 0],
      );
      expect(engine.texts, isNot(contains('never-index-this-password')));

      repository.current = generation;
      final fresh = await service.buildStatus(
        secrets: <SecretItem>[_secret()],
        notes: const [],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );
      expect(fresh.pendingItems, isEmpty);
    },
  );

  test(
    'non-index source timestamp changes do not invalidate matching content',
    () async {
      final repository = _RecordingEmbeddingIndexRepository();
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'root-key-1',
            searchIndexFingerprintKey: Uint8List.fromList(
              List<int>.generate(32, (index) => index),
            ),
          ),
        );
      addTearDown(keyStore.clear);
      final service = SearchIndexService(
        repository: repository,
        cryptoService: _SearchIndexCryptoService(),
        embeddingEngine: _RecordingEmbeddingEngine(),
        sessionKeyStore: keyStore,
      );
      final configuration = SearchConfiguration.defaults();
      final original = _secret();
      final initial = await service.buildStatus(
        secrets: <SecretItem>[original],
        notes: const [],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );
      await service.indexPendingItems(
        items: initial.pendingItems,
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      final timestampOnlyUpdate = SecretItem(
        id: original.id,
        vaultId: original.vaultId,
        title: original.title,
        usernameCiphertext: original.usernameCiphertext,
        passwordCiphertext: original.passwordCiphertext,
        websiteUrlCiphertext: original.websiteUrlCiphertext,
        noteCiphertext: original.noteCiphertext,
        tags: original.tags,
        categoryId: 'category-only-change',
        favorite: true,
        createdAt: original.createdAt,
        updatedAt: original.updatedAt.add(const Duration(seconds: 1)),
      );

      final status = await service.buildStatus(
        secrets: <SecretItem>[timestampOnlyUpdate],
        notes: const [],
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      expect(status.pendingItems, isEmpty);
    },
  );
}

class _RecordingEmbeddingIndexRepository implements EmbeddingIndexRepository {
  EmbeddingIndexSet? current;
  final List<EmbeddingIndexSet> replacements = <EmbeddingIndexSet>[];

  @override
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  ) async {
    final value = current;
    return value?.sourceKey == sourceKey && value?.modelId == modelId
        ? value
        : null;
  }

  @override
  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey) async {
    if (current?.sourceKey == sourceKey) {
      current = null;
    }
  }

  @override
  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet) async {
    replacements.add(indexSet);
    current = indexSet;
    return true;
  }
}

class _RecordingEmbeddingEngine implements EmbeddingEngine {
  final List<String> texts = <String>[];

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    texts.add(request.text);
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

class _SearchIndexCryptoService implements CryptoService {
  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return switch (context.column) {
      'username_ciphertext' => 'alice@example.test',
      'password_ciphertext' => 'never-index-this-password',
      'website_url_ciphertext' => 'https://example.test',
      'note_ciphertext' => 'MFA enabled',
      _ => '',
    };
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    throw UnimplementedError();
  }
}

SecretItem _secret() {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return SecretItem(
    id: 'secret-1',
    vaultId: 'default',
    title: 'Example account',
    usernameCiphertext: const <int>[1],
    passwordCiphertext: const <int>[2],
    websiteUrlCiphertext: const <int>[3],
    noteCiphertext: const <int>[4],
    tags: const <String>['Work'],
    categoryId: null,
    favorite: false,
    createdAt: now,
    updatedAt: now,
  );
}

const ModelRegistryEntry _model = ModelRegistryEntry(
  id: 'model-1',
  type: 'embedding',
  provider: 'local',
  name: 'Embedding',
  version: '1',
  sizeBytes: 1,
  quantization: 'fp32',
  minRamMb: 1,
  recommendedTier: 'small',
  localPath: 'model.onnx',
  checksum: 'sha256:model',
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
);
