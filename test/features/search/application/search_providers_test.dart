import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/lock_session.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_set.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';

class _FakeCryptoService implements CryptoService {
  const _FakeCryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    if (ciphertext == null) {
      return '';
    }
    return String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    return plaintext == null ? null : Uint8List.fromList(plaintext.codeUnits);
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

class _FakeSearchIndexService extends SearchIndexService {
  _FakeSearchIndexService()
    : super(
        repository: _FakeEmbeddingIndexRepository(),
        cryptoService: const _FakeCryptoService(),
        embeddingEngine: const _FakeEmbeddingEngine(),
      );

  @override
  Future<int> indexCorpusPending({
    required String activeVaultId,
    required SearchCorpusReader corpus,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async => 0;

  @override
  Future<void> indexPendingItems({
    required List<SearchIndexPendingItem> items,
    required ModelRegistryEntry activeEmbeddingModel,
    required String modelRevisionHash,
    required SearchConfiguration configuration,
  }) async {}
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

SearchIndexStatus _readyStatus() {
  return const SearchIndexStatus(
    engineReady: true,
    engineReason: 'ready',
    hasActiveEmbeddingModel: true,
    pendingItems: <SearchIndexPendingItem>[],
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

List<SearchResultItem> _results(List<String> ids) {
  return ids
      .map(
        (id) => SearchResultItem(
          id: id,
          type: SearchResultType.secret,
          title: 'Title $id',
          preview: 'Preview $id',
          tags: const <String>[],
          favorite: false,
          updatedAt: DateTime(2026, 4, 22),
        ),
      )
      .toList(growable: false);
}

SearchResultItem _result(String id, SearchResultType type) {
  return SearchResultItem(
    id: id,
    type: type,
    title: 'Title $id',
    preview: 'Preview $id',
    tags: const <String>[],
    favorite: false,
    updatedAt: DateTime(2026, 4, 22),
  );
}

void main() {
  test(
    'indexPendingAndRefresh writes empty-query feedback after refresh completes',
    () async {
      final container = ProviderContainer(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => LockSessionController()..markUnlocked(UnlockMethod.pin),
          ),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          defaultVaultProvider.overrideWith((ref) async => _defaultVault()),
          searchCorpusReaderProvider.overrideWith(
            (ref) => _emptyCorpusReader(),
          ),
          cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
          searchQueryProvider.overrideWith((ref) => ''),
          searchIndexStatusSnapshotProvider.overrideWith(
            (ref) async => _readyStatus(),
          ),
          activeEmbeddingModelProvider.overrideWith(
            (ref) async => _fakeEmbeddingModel,
          ),
          searchIndexSettingsProvider.overrideWith(
            (ref) async => const SearchIndexSettings.defaults(),
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
          searchIndexModelRevisionProvider(
            _fakeEmbeddingModel,
          ).overrideWith((ref) async => 'a' * 64),
          searchIndexServiceProvider.overrideWith(
            (ref) => _FakeSearchIndexService(),
          ),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => const <SearchResultItem>[],
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(searchRefreshControllerProvider.notifier)
          .refresh(container.read(searchQueryProvider));

      final feedback = container.read(searchRefreshFeedbackProvider);
      expect(feedback.visible, isTrue);
      expect(feedback.headline, '搜索状态已刷新');
      expect(feedback.message, '输入关键词后可查看最新结果。');
      expect(feedback.changed, isNull);
    },
  );

  test(
    'indexPendingAndRefresh writes unchanged feedback when unified result ids stay the same',
    () async {
      final container = ProviderContainer(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => LockSessionController()..markUnlocked(UnlockMethod.pin),
          ),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          defaultVaultProvider.overrideWith((ref) async => _defaultVault()),
          searchCorpusReaderProvider.overrideWith(
            (ref) => _emptyCorpusReader(),
          ),
          cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
          searchQueryProvider.overrideWith((ref) => 'bank'),
          searchIndexStatusSnapshotProvider.overrideWith(
            (ref) async => _readyStatus(),
          ),
          activeEmbeddingModelProvider.overrideWith(
            (ref) async => _fakeEmbeddingModel,
          ),
          searchIndexSettingsProvider.overrideWith(
            (ref) async => const SearchIndexSettings.defaults(),
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
          searchIndexModelRevisionProvider(
            _fakeEmbeddingModel,
          ).overrideWith((ref) async => 'a' * 64),
          searchIndexServiceProvider.overrideWith(
            (ref) => _FakeSearchIndexService(),
          ),
          unifiedSearchResultsProvider.overrideWith(
            (ref) async => _results(['a', 'b']),
          ),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(searchRefreshControllerProvider.notifier)
          .refresh(container.read(searchQueryProvider));

      final feedback = container.read(searchRefreshFeedbackProvider);
      expect(feedback.visible, isTrue);
      expect(feedback.changed, isFalse);
      expect(feedback.message, '当前结果已更新，本轮刷新未改变当前结果。');
    },
  );

  test(
    'indexPendingAndRefresh writes changed-count feedback when result count changes',
    () async {
      var callCount = 0;
      final container = ProviderContainer(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => LockSessionController()..markUnlocked(UnlockMethod.pin),
          ),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          defaultVaultProvider.overrideWith((ref) async => _defaultVault()),
          searchCorpusReaderProvider.overrideWith(
            (ref) => _emptyCorpusReader(),
          ),
          cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
          searchQueryProvider.overrideWith((ref) => 'bank'),
          searchIndexStatusSnapshotProvider.overrideWith(
            (ref) async => _readyStatus(),
          ),
          activeEmbeddingModelProvider.overrideWith(
            (ref) async => _fakeEmbeddingModel,
          ),
          searchIndexSettingsProvider.overrideWith(
            (ref) async => const SearchIndexSettings.defaults(),
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
          searchIndexModelRevisionProvider(
            _fakeEmbeddingModel,
          ).overrideWith((ref) async => 'a' * 64),
          searchIndexServiceProvider.overrideWith(
            (ref) => _FakeSearchIndexService(),
          ),
          unifiedSearchResultsProvider.overrideWith((ref) async {
            callCount++;
            return callCount == 1 ? _results(['a']) : _results(['a', 'b', 'c']);
          }),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(searchRefreshControllerProvider.notifier)
          .refresh(container.read(searchQueryProvider));

      final feedback = container.read(searchRefreshFeedbackProvider);
      expect(feedback.visible, isTrue);
      expect(feedback.changed, isTrue);
      expect(feedback.message, '当前结果已更新，结果数量从 1 条变为 3 条。');
    },
  );

  test(
    'indexPendingAndRefresh writes reorder feedback when ids change order with same count',
    () async {
      var callCount = 0;
      final container = ProviderContainer(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => LockSessionController()..markUnlocked(UnlockMethod.pin),
          ),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          defaultVaultProvider.overrideWith((ref) async => _defaultVault()),
          searchCorpusReaderProvider.overrideWith(
            (ref) => _emptyCorpusReader(),
          ),
          cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
          searchQueryProvider.overrideWith((ref) => 'bank'),
          searchIndexStatusSnapshotProvider.overrideWith(
            (ref) async => _readyStatus(),
          ),
          activeEmbeddingModelProvider.overrideWith(
            (ref) async => _fakeEmbeddingModel,
          ),
          searchIndexSettingsProvider.overrideWith(
            (ref) async => const SearchIndexSettings.defaults(),
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
          searchIndexModelRevisionProvider(
            _fakeEmbeddingModel,
          ).overrideWith((ref) async => 'a' * 64),
          searchIndexServiceProvider.overrideWith(
            (ref) => _FakeSearchIndexService(),
          ),
          unifiedSearchResultsProvider.overrideWith((ref) async {
            callCount++;
            return callCount == 1 ? _results(['a', 'b']) : _results(['b', 'a']);
          }),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(searchRefreshControllerProvider.notifier)
          .refresh(container.read(searchQueryProvider));

      final feedback = container.read(searchRefreshFeedbackProvider);
      expect(feedback.visible, isTrue);
      expect(feedback.changed, isTrue);
      expect(feedback.message, '当前结果已更新，本轮刷新调整了结果排序。');
    },
  );

  test(
    'indexPendingAndRefresh treats Secret and Note with the same id as different results',
    () async {
      var callCount = 0;
      final container = ProviderContainer(
        overrides: [
          lockSessionControllerProvider.overrideWith(
            (ref) => LockSessionController()..markUnlocked(UnlockMethod.pin),
          ),
          sensitiveStateAccessAllowedProvider.overrideWith((ref) => true),
          defaultVaultProvider.overrideWith((ref) async => _defaultVault()),
          searchCorpusReaderProvider.overrideWith(
            (ref) => _emptyCorpusReader(),
          ),
          cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
          searchQueryProvider.overrideWith((ref) => 'bank'),
          searchIndexStatusSnapshotProvider.overrideWith(
            (ref) async => _readyStatus(),
          ),
          activeEmbeddingModelProvider.overrideWith(
            (ref) async => _fakeEmbeddingModel,
          ),
          searchIndexSettingsProvider.overrideWith(
            (ref) async => const SearchIndexSettings.defaults(),
          ),
          searchConfigurationProvider.overrideWith(
            (ref) async => SearchConfiguration.defaults(),
          ),
          searchIndexModelRevisionProvider(
            _fakeEmbeddingModel,
          ).overrideWith((ref) async => 'a' * 64),
          searchIndexServiceProvider.overrideWith(
            (ref) => _FakeSearchIndexService(),
          ),
          unifiedSearchResultsProvider.overrideWith((ref) async {
            callCount++;
            return callCount == 1
                ? <SearchResultItem>[_result('same', SearchResultType.secret)]
                : <SearchResultItem>[_result('same', SearchResultType.note)];
          }),
          semanticSearchResultsProvider.overrideWith(
            (ref) async => const <SemanticSearchResult>[],
          ),
        ],
      );

      addTearDown(container.dispose);

      await container
          .read(searchRefreshControllerProvider.notifier)
          .refresh(container.read(searchQueryProvider));

      final feedback = container.read(searchRefreshFeedbackProvider);
      expect(feedback.changed, isTrue);
      expect(feedback.message, '当前结果已更新，本轮刷新调整了结果排序。');
    },
  );
}
