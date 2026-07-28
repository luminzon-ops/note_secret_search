import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';

void main() {
  test(
    'index status provider scans the scoped corpus without materializing lists',
    () async {
      final service = _FakeSearchIndexService(
        corpusStatus: const SearchIndexStatus(
          engineReady: true,
          engineReason: 'ready',
          hasActiveEmbeddingModel: true,
          pendingItems: <SearchIndexPendingItem>[],
          pendingCount: 257,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          defaultVaultProvider.overrideWith((ref) async => _defaultVault()),
          secretListProvider.overrideWith(
            (ref) async => throw StateError('unbounded secret load'),
          ),
          noteListProvider.overrideWith(
            (ref) async => throw StateError('unbounded note load'),
          ),
          activeEmbeddingModelProvider.overrideWith(
            (ref) async => _fakeEmbeddingModel,
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
          searchIndexModelRevisionProvider(
            _fakeEmbeddingModel,
          ).overrideWith((ref) async => 'a' * 64),
          searchCorpusReaderProvider.overrideWith(
            (ref) => _emptyCorpusReader(),
          ),
          searchIndexServiceProvider.overrideWith((ref) => service),
        ],
      );
      addTearDown(container.dispose);

      final status = await container.read(searchIndexStatusProvider.future);

      expect(status.pendingCount, 257);
      expect(service.buildCorpusStatusCalls, 1);
      expect(service.lastActiveVaultId, 'default');
    },
  );

  test('indexPending reports the paged runner replacement count', () async {
    final service = _FakeSearchIndexService(corpusReplacementCount: 257);
    final container = ProviderContainer(
      overrides: [
        lockSessionControllerProvider.overrideWith(
          (ref) => LockSessionController()..markUnlocked(UnlockMethod.pin),
        ),
        sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
        defaultVaultProvider.overrideWith((ref) async => _defaultVault()),
        searchCorpusReaderProvider.overrideWith((ref) => _emptyCorpusReader()),
        searchIndexStatusProvider.overrideWith(
          (ref) async => const SearchIndexStatus(
            engineReady: true,
            engineReason: 'ready',
            hasActiveEmbeddingModel: true,
            pendingItems: <SearchIndexPendingItem>[],
            pendingCount: 257,
          ),
        ),
        activeEmbeddingModelProvider.overrideWith(
          (ref) async => _fakeEmbeddingModel,
        ),
        searchConfigurationProvider.overrideWith(
          (ref) async => SearchConfiguration.defaults(),
        ),
        searchIndexModelRevisionProvider(
          _fakeEmbeddingModel,
        ).overrideWith((ref) async => 'a' * 64),
        searchIndexServiceProvider.overrideWith((ref) => service),
      ],
    );
    addTearDown(container.dispose);

    await container.read(searchIndexControllerProvider).indexPending();

    expect(service.indexCorpusPendingCalls, 1);
    expect(container.read(searchIndexTaskStateProvider).lastIndexedCount, 257);
  });
}

class _FakeSearchIndexService extends SearchIndexService {
  _FakeSearchIndexService({
    this.corpusStatus = const SearchIndexStatus(
      engineReady: true,
      engineReason: 'ready',
      hasActiveEmbeddingModel: true,
      pendingItems: <SearchIndexPendingItem>[],
    ),
    this.corpusReplacementCount = 0,
  }) : super(
         repository: _FakeEmbeddingIndexRepository(),
         cryptoService: const _FakeCryptoService(),
         embeddingEngine: const _FakeEmbeddingEngine(),
       );

  final SearchIndexStatus corpusStatus;
  final int corpusReplacementCount;
  int buildCorpusStatusCalls = 0;
  int indexCorpusPendingCalls = 0;
  String? lastActiveVaultId;

  @override
  Future<SearchIndexStatus> buildCorpusStatus({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required ModelRegistryEntry? activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    buildCorpusStatusCalls++;
    lastActiveVaultId = activeVaultId;
    return corpusStatus;
  }

  @override
  Future<int> indexCorpusPending({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {
    indexCorpusPendingCalls++;
    lastActiveVaultId = activeVaultId;
    return corpusReplacementCount;
  }
}

class _FakeEmbeddingIndexRepository implements EmbeddingIndexRepository {
  @override
  Future<EmbeddingIndexSet?> getIndexSetBySource(
    SearchSourceKey sourceKey,
    String modelId,
  ) async => null;

  @override
  Future<void> removeIndexSetsBySource(SearchSourceKey sourceKey) async {}

  @override
  Future<bool> replaceIndexSet(EmbeddingIndexSet indexSet) async => true;
}

class _FakeEmbeddingEngine implements EmbeddingEngine {
  const _FakeEmbeddingEngine();

  @override
  Future<EmbeddingVector> embed(EmbeddingRequest request) async {
    return const EmbeddingVector(values: <double>[0.1, 0.2], tokenCount: 2);
  }

  @override
  Future<EmbeddingEngineState> getState(ModelRegistryEntry model) async {
    return const EmbeddingEngineState(
      ready: true,
      reason: 'ready',
      status: EmbeddingRuntimeStatus.ready,
    );
  }
}

class _FakeCryptoService implements CryptoService {
  const _FakeCryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return ciphertext == null ? '' : String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    return plaintext == null ? null : Uint8List.fromList(plaintext.codeUnits);
  }
}

class _UnusedSecretRepository implements SecretRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedNoteRepository implements NoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SearchCorpusReader _emptyCorpusReader() {
  return SearchCorpusReader(
    secretRepository: _UnusedSecretRepository(),
    noteRepository: _UnusedNoteRepository(),
  );
}

Vault _defaultVault() {
  final now = DateTime(2026, 7, 21);
  return Vault(
    id: 'default',
    name: 'Default',
    description: null,
    isDefault: true,
    encryptionVersion: 1,
    createdAt: now,
    updatedAt: now,
  );
}

const _fakeEmbeddingModel = ModelRegistryEntry(
  id: 'embed-1',
  type: 'embedding',
  provider: 'builtin',
  name: 'MiniLM',
  version: '1.0',
  sizeBytes: 1024,
  quantization: 'Q8',
  minRamMb: 512,
  recommendedTier: 'mvp',
  localPath: '/models/minilm.onnx',
  checksum: 'abc',
  enabled: true,
  installedAt: null,
  filePresent: true,
);
