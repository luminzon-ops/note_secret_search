import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';

void main() {
  test(
    'paged index runner processes every source and repeated runs are no-ops',
    () async {
      final repository = _CorpusIndexRepository();
      final sources = _PagedIndexSecretRepository(<SecretItem>[
        for (var index = 0; index < 257; index++)
          _secret(id: 'secret-${index.toString().padLeft(3, '0')}'),
      ]);
      final keyStore = DatabaseSessionKeyStore()
        ..replace(
          DatabaseSessionKeys(
            databaseKey: Uint8List(32),
            fieldKey: Uint8List(32),
            keyId: 'root-key-1',
            searchIndexFingerprintKey: Uint8List(32),
          ),
        );
      addTearDown(keyStore.clear);
      final service = SearchIndexService(
        repository: repository,
        cryptoService: _SearchIndexCryptoService(),
        embeddingEngine: _RecordingEmbeddingEngine(),
        sessionKeyStore: keyStore,
      );
      final corpus = SearchCorpusReader(
        secretRepository: sources,
        noteRepository: _EmptyIndexNoteRepository(),
      );
      final configuration = SearchConfiguration.defaults().copyWith(
        includeUsername: false,
        includeUrl: false,
        includeSecretNote: false,
        includeTags: false,
        includeNoteBody: false,
      );

      final status = await service.buildCorpusStatus(
        activeVaultId: 'default',
        corpus: corpus,
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );
      expect(status.pendingCount, 257);
      expect(status.pendingItems, hasLength(searchIndexPendingPreviewLimit));

      final first = await service.indexCorpusPending(
        activeVaultId: 'default',
        corpus: corpus,
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );
      final second = await service.indexCorpusPending(
        activeVaultId: 'default',
        corpus: corpus,
        activeEmbeddingModel: _model,
        modelRevisionHash: 'a' * 64,
        configuration: configuration,
      );

      expect(first, 257);
      expect(second, 0);
      expect(repository.replacementCount, 257);
      expect(sources.completedPageSizes.take(3), const <int>[128, 128, 1]);
    },
  );
}

class _CorpusIndexRepository
    implements EmbeddingIndexRepository, EmbeddingIndexHeaderRepository {
  final Map<SearchSourceKey, EmbeddingIndexSet> sets =
      <SearchSourceKey, EmbeddingIndexSet>{};
  int replacementCount = 0;

  @override
  Future<Map<SearchSourceKey, EmbeddingIndexSetHeader>>
  getIndexSetHeadersBySources(
    Iterable<SearchSourceKey> sourceKeys,
    String modelId,
  ) async {
    return <SearchSourceKey, EmbeddingIndexSetHeader>{
      for (final key in sourceKeys)
        if (sets[key] case final set?)
          if (set.modelId == modelId) key: EmbeddingIndexSetHeader.fromSet(set),
    };
  }

  @override
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  ) async {
    final set = sets[sourceKey];
    return set?.modelId == modelId ? set : null;
  }

  @override
  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey) async {
    sets.remove(sourceKey);
  }

  @override
  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet) async {
    sets[indexSet.sourceKey] = indexSet;
    replacementCount++;
    return true;
  }
}

class _PagedIndexSecretRepository
    implements SecretRepository, SecretSearchReader {
  _PagedIndexSecretRepository(this.items);

  final List<SecretItem> items;
  final List<int> completedPageSizes = <int>[];

  @override
  Future<List<SecretItem>> listByVaultPage(
    String vaultId, {
    String? afterId,
    int limit = searchSourcePageSize,
  }) async {
    final page = items
        .where(
          (item) =>
              item.vaultId == vaultId &&
              item.deletedAt == null &&
              (afterId == null || item.id.compareTo(afterId) > 0),
        )
        .take(limit)
        .toList(growable: false);
    if (page.isNotEmpty) {
      completedPageSizes.add(page.length);
    }
    return page;
  }

  @override
  Future<List<SecretItem>> listByVault(String vaultId) {
    throw StateError('unbounded secret load');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyIndexNoteRepository implements NoteRepository, NoteSearchReader {
  @override
  Future<List<NoteItem>> listByVaultPage(
    String vaultId, {
    String? afterId,
    int limit = searchSourcePageSize,
  }) async {
    return const <NoteItem>[];
  }

  @override
  Future<List<NoteItem>> listByVault(String vaultId) {
    throw StateError('unbounded note load');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingEmbeddingEngine implements EmbeddingEngine {
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

SecretItem _secret({required String id}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return SecretItem(
    id: id,
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
