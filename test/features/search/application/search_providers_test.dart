import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

class _FakeCryptoService implements CryptoService {
  const _FakeCryptoService();

  @override
  String decryptNullable(List<int>? ciphertext) {
    if (ciphertext == null) {
      return '';
    }
    return String.fromCharCodes(ciphertext);
  }

  @override
  List<int>? encryptNullable(String? plaintext) => plaintext?.codeUnits;
}

class _FakeSearchRepository implements SearchRepository {
  @override
  Future<List<EmbeddingChunk>> getChunksBySource(
    String sourceId,
    SearchSourceType sourceType,
    String modelId,
  ) async {
    return const <EmbeddingChunk>[];
  }

  @override
  Future<SearchScopeConfig> loadScopeConfig() async => const SearchScopeConfig.defaults();

  @override
  Future<void> removeChunksBySource(String sourceId, SearchSourceType sourceType) async {}

  @override
  Future<void> saveScopeConfig(SearchScopeConfig config) async {}

  @override
  Future<void> upsertEmbeddingChunks(List<EmbeddingChunk> chunks) async {}
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
          repository: _FakeSearchRepository(),
          cryptoService: const _FakeCryptoService(),
          embeddingEngine: const _FakeEmbeddingEngine(),
        );

  @override
  Future<void> indexPendingItems({
    required List<SearchIndexPendingItem> items,
    required ModelRegistryEntry activeEmbeddingModel,
    required SearchIndexSettings settings,
  }) async {}
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

void main() {
  test('indexPendingAndRefresh writes empty-query feedback after refresh completes', () async {
    final container = ProviderContainer(
      overrides: [
        cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
        searchQueryProvider.overrideWith((ref) => ''),
        searchIndexStatusProvider.overrideWith((ref) async => _readyStatus()),
        activeEmbeddingModelProvider.overrideWith((ref) async => _fakeEmbeddingModel),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        searchIndexServiceProvider.overrideWith((ref) => _FakeSearchIndexService()),
        unifiedSearchResultsProvider.overrideWith((ref) async => const <SearchResultItem>[]),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
    );

    addTearDown(container.dispose);

    await container.read(searchIndexControllerProvider).indexPendingAndRefresh();

    final feedback = container.read(searchRefreshFeedbackProvider);
    expect(feedback.visible, isTrue);
    expect(feedback.headline, '搜索状态已刷新');
    expect(feedback.message, '输入关键词后可查看最新结果。');
    expect(feedback.changed, isNull);
  });

  test('indexPendingAndRefresh writes unchanged feedback when unified result ids stay the same', () async {
    final container = ProviderContainer(
      overrides: [
        cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
        searchQueryProvider.overrideWith((ref) => 'bank'),
        searchIndexStatusProvider.overrideWith((ref) async => _readyStatus()),
        activeEmbeddingModelProvider.overrideWith((ref) async => _fakeEmbeddingModel),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        searchIndexServiceProvider.overrideWith((ref) => _FakeSearchIndexService()),
        unifiedSearchResultsProvider.overrideWith((ref) async => _results(['a', 'b'])),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
    );

    addTearDown(container.dispose);

    await container.read(searchIndexControllerProvider).indexPendingAndRefresh();

    final feedback = container.read(searchRefreshFeedbackProvider);
    expect(feedback.visible, isTrue);
    expect(feedback.changed, isFalse);
    expect(feedback.message, '当前结果已更新，本轮刷新未改变当前结果。');
  });

  test('indexPendingAndRefresh writes changed-count feedback when result count changes', () async {
    var callCount = 0;
    final container = ProviderContainer(
      overrides: [
        cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
        searchQueryProvider.overrideWith((ref) => 'bank'),
        searchIndexStatusProvider.overrideWith((ref) async => _readyStatus()),
        activeEmbeddingModelProvider.overrideWith((ref) async => _fakeEmbeddingModel),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        searchIndexServiceProvider.overrideWith((ref) => _FakeSearchIndexService()),
        unifiedSearchResultsProvider.overrideWith((ref) async {
          callCount++;
          return callCount == 1 ? _results(['a']) : _results(['a', 'b', 'c']);
        }),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
    );

    addTearDown(container.dispose);

    await container.read(searchIndexControllerProvider).indexPendingAndRefresh();

    final feedback = container.read(searchRefreshFeedbackProvider);
    expect(feedback.visible, isTrue);
    expect(feedback.changed, isTrue);
    expect(feedback.message, '当前结果已更新，结果数量从 1 条变为 3 条。');
  });

  test('indexPendingAndRefresh writes reorder feedback when ids change order with same count', () async {
    var callCount = 0;
    final container = ProviderContainer(
      overrides: [
        cryptoServiceProvider.overrideWithValue(const _FakeCryptoService()),
        searchQueryProvider.overrideWith((ref) => 'bank'),
        searchIndexStatusProvider.overrideWith((ref) async => _readyStatus()),
        activeEmbeddingModelProvider.overrideWith((ref) async => _fakeEmbeddingModel),
        searchIndexSettingsProvider.overrideWith((ref) async => const SearchIndexSettings.defaults()),
        searchIndexServiceProvider.overrideWith((ref) => _FakeSearchIndexService()),
        unifiedSearchResultsProvider.overrideWith((ref) async {
          callCount++;
          return callCount == 1 ? _results(['a', 'b']) : _results(['b', 'a']);
        }),
        semanticSearchResultsProvider.overrideWith((ref) async => const <SemanticSearchResult>[]),
      ],
    );

    addTearDown(container.dispose);

    await container.read(searchIndexControllerProvider).indexPendingAndRefresh();

    final feedback = container.read(searchRefreshFeedbackProvider);
    expect(feedback.visible, isTrue);
    expect(feedback.changed, isTrue);
    expect(feedback.message, '当前结果已更新，本轮刷新调整了结果排序。');
  });
}
