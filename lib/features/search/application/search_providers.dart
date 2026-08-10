import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_sensitive_providers.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_use_cases.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/application/search_lock_guard.dart';
import 'package:note_secret_search/features/search/application/search_refresh_controller.dart';
import 'package:note_secret_search/features/search/application/search_service.dart';
import 'package:note_secret_search/features/search/application/semantic_search_readiness_providers.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';

export 'search_index_use_cases.dart'
    show
        SearchIndexExecutionResult,
        SearchIndexRunner,
        SearchIndexTaskStateWriter,
        SearchRefreshExecutionResult,
        SearchRefreshFeedbackWriter,
        SearchRefreshPhaseWriter,
        SearchRefreshRunner;
export 'search_lock_guard.dart';
export 'search_refresh_controller.dart';
export 'search_refresh_state.dart';

final sqliteEmbeddingRepositoryProvider = Provider<SearchEmbeddingRepository>((
  ref,
) {
  throw StateError(
    'sqliteEmbeddingRepositoryProvider must be overridden by app composition',
  );
});

final searchLockGuardProvider = Provider<SearchLockGuard>((ref) {
  final guard = SearchLockGuard(
    accessAllowed: ref.read(sensitiveStateAccessAllowedProvider),
  );
  ref.listen<bool>(sensitiveStateAccessAllowedProvider, (_, next) {
    guard.updateAccess(next);
  });
  return guard;
});

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(cryptoService: ref.watch(cryptoServiceProvider));
});

final searchCorpusReaderProvider = Provider<SearchCorpusReader>((ref) {
  return SearchCorpusReader(
    secretRepository: ref.watch(secretRepositoryProvider),
    noteRepository: ref.watch(noteRepositoryProvider),
  );
});

final searchFusionServiceProvider = Provider<SearchFusionService>((ref) {
  return const SearchFusionService();
});

final searchIndexServiceProvider = Provider<SearchIndexService>((ref) {
  return SearchIndexService(
    repository: ref.watch(sqliteEmbeddingRepositoryProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
    embeddingEngine: ref.watch(embeddingEngineProvider),
    sessionKeyStore: ref.watch(databaseSessionKeyStoreProvider),
    writeFence: ref.watch(searchIndexWriteFenceProvider),
  );
});

final semanticSearchServiceProvider = Provider<SemanticSearchService>((ref) {
  return SemanticSearchService(
    repository: ref.watch(sqliteEmbeddingRepositoryProvider),
    embeddingEngine: ref.watch(embeddingEngineProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
    sessionKeyStore: ref.watch(databaseSessionKeyStoreProvider),
  );
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final keywordSearchResultsProvider = FutureProvider<List<SearchResultItem>>((
  ref,
) {
  return guardSensitiveFuture<List<SearchResultItem>>(
    ref,
    lockedValue: const <SearchResultItem>[],
    load: () async {
      final query = ref.watch(searchQueryProvider).trim();
      if (query.isEmpty) {
        return const <SearchResultItem>[];
      }

      final configuration = await ref.watch(searchConfigurationProvider.future);
      final vault = await ref.watch(defaultVaultProvider.future);
      if (vault == null) {
        return const <SearchResultItem>[];
      }
      return ref
          .watch(searchServiceProvider)
          .searchCorpus(
            activeVaultId: vault.id,
            query: query,
            configuration: configuration,
            corpus: ref.watch(searchCorpusReaderProvider),
          );
    },
  );
});

const _lockedSearchIndexStatus = SearchIndexStatus(
  engineReady: false,
  engineReason: '应用已锁定。',
  hasActiveEmbeddingModel: false,
  pendingItems: <SearchIndexPendingItem>[],
);

final FutureProvider<SearchIndexStatus>
searchIndexStatusSnapshotProvider = FutureProvider<SearchIndexStatus>((ref) {
  return guardSensitiveFuture<SearchIndexStatus>(
    ref,
    lockedValue: _lockedSearchIndexStatus,
    load: () async {
      final vault = await ref.watch(defaultVaultProvider.future);
      final activeModel = await ref.watch(activeEmbeddingModelProvider.future);
      final configuration = await ref.watch(searchConfigurationProvider.future);
      final modelRevisionHash = activeModel == null
          ? ''
          : await ref.watch(
              searchIndexModelRevisionProvider(activeModel).future,
            );
      final indexService = ref.watch(searchIndexServiceProvider);
      final baseStatus = vault == null
          ? await indexService.buildStatus(
              secrets: const [],
              notes: const [],
              activeEmbeddingModel: activeModel,
              modelRevisionHash: modelRevisionHash,
              configuration: configuration,
            )
          : await indexService.buildCorpusStatus(
              activeVaultId: vault.id,
              corpus: ref.watch(searchCorpusReaderProvider),
              activeEmbeddingModel: activeModel,
              modelRevisionHash: modelRevisionHash,
              configuration: configuration,
            );
      return baseStatus;
    },
  );
});

final FutureProvider<SearchIndexStatus> searchIndexStatusProvider =
    FutureProvider<SearchIndexStatus>((ref) {
      final taskState = ref.watch(searchIndexTaskStateProvider);
      if (!ref.watch(sensitiveStateAccessAllowedProvider)) {
        return _lockedSearchIndexStatus.copyWith(taskState: taskState);
      }
      return ref
          .watch(searchIndexStatusSnapshotProvider.future)
          .then((baseStatus) => baseStatus.copyWith(taskState: taskState));
    });

final semanticSearchResultsProvider =
    FutureProvider<List<SemanticSearchResult>>((ref) {
      return guardSensitiveFuture<List<SemanticSearchResult>>(
        ref,
        lockedValue: const <SemanticSearchResult>[],
        load: () async {
          final query = ref.watch(searchQueryProvider).trim();
          if (query.isEmpty) {
            return const <SemanticSearchResult>[];
          }

          final readiness = await ref.watch(
            semanticSearchReadinessProvider.future,
          );
          if (!readiness.ready || readiness.activeEmbeddingModel == null) {
            return const <SemanticSearchResult>[];
          }

          final configuration = await ref.watch(
            searchConfigurationProvider.future,
          );
          final vault = await ref.watch(defaultVaultProvider.future);
          if (vault == null) {
            return const <SemanticSearchResult>[];
          }
          final modelRevisionHash = await ref.watch(
            searchIndexModelRevisionProvider(
              readiness.activeEmbeddingModel!,
            ).future,
          );
          return ref
              .watch(semanticSearchServiceProvider)
              .searchCorpus(
                activeVaultId: vault.id,
                query: query,
                configuration: configuration,
                modelRevisionHash: modelRevisionHash,
                activeEmbeddingModel: readiness.activeEmbeddingModel!,
                corpus: ref.watch(searchCorpusReaderProvider),
              );
        },
      );
    });

final unifiedSearchResultsProvider = FutureProvider<List<SearchResultItem>>((
  ref,
) {
  return guardSensitiveFuture<List<SearchResultItem>>(
    ref,
    lockedValue: const <SearchResultItem>[],
    load: () async {
      final keywordResults = await ref.watch(
        keywordSearchResultsProvider.future,
      );
      final semanticResults = await ref.watch(
        semanticSearchResultsProvider.future,
      );
      return ref
          .watch(searchFusionServiceProvider)
          .fuse(
            keywordResults: keywordResults,
            semanticResults: semanticResults,
            query: ref.watch(searchQueryProvider),
          );
    },
  );
});

final Provider<SearchIndexRunner> indexPendingSearchUseCaseProvider =
    Provider<SearchIndexRunner>((ref) {
      return IndexPendingSearchUseCase(
        lockGuard: ref.watch(searchLockGuardProvider),
        loadIndexStatus: () {
          return ref.read(searchIndexStatusSnapshotProvider.future);
        },
        loadActiveEmbeddingModel: () {
          return ref.read(activeEmbeddingModelProvider.future);
        },
        loadConfiguration: () {
          return ref.read(searchConfigurationProvider.future);
        },
        loadDefaultVault: () {
          return ref.read(defaultVaultProvider.future);
        },
        loadModelRevisionHash: (model) {
          return ref.read(searchIndexModelRevisionProvider(model).future);
        },
        loadCorpusReader: () {
          return ref.read(searchCorpusReaderProvider);
        },
        loadIndexService: () {
          return ref.read(searchIndexServiceProvider);
        },
        invalidateIndexStatus: () {
          ref.invalidate(searchIndexStatusSnapshotProvider);
        },
      );
    });

final Provider<SearchRefreshRunner> refreshSearchIndexUseCaseProvider =
    Provider<SearchRefreshRunner>((ref) {
      return RefreshSearchIndexUseCase(
        lockGuard: ref.watch(searchLockGuardProvider),
        indexRunner: ref.watch(indexPendingSearchUseCaseProvider),
        loadUnifiedResults: () {
          return ref.read(unifiedSearchResultsProvider.future);
        },
        invalidateIndexStatus: () {
          ref.invalidate(searchIndexStatusSnapshotProvider);
        },
        invalidateSemanticResults: () {
          ref.invalidate(semanticSearchResultsProvider);
        },
        invalidateUnifiedResults: () {
          ref.invalidate(unifiedSearchResultsProvider);
        },
        awaitIndexStatus: () {
          return ref.read(searchIndexStatusSnapshotProvider.future);
        },
        awaitSemanticResults: () async {
          await ref.read(semanticSearchResultsProvider.future);
        },
        awaitUnifiedResults: () {
          return ref.read(unifiedSearchResultsProvider.future);
        },
      );
    });

final StateNotifierProvider<SearchRefreshController, SearchRefreshState>
searchRefreshControllerProvider =
    StateNotifierProvider<SearchRefreshController, SearchRefreshState>((ref) {
      return SearchRefreshController(
        refreshRunner: ref.watch(refreshSearchIndexUseCaseProvider),
        indexRunner: ref.watch(indexPendingSearchUseCaseProvider),
        lockGuard: ref.watch(searchLockGuardProvider),
      );
    });

final Provider<SearchIndexTaskState> searchIndexTaskStateProvider =
    Provider<SearchIndexTaskState>((ref) {
      return ref.watch(
        searchRefreshControllerProvider.select((state) => state.task),
      );
    });

final Provider<SearchRefreshSessionState> searchRefreshSessionProvider =
    Provider<SearchRefreshSessionState>((ref) {
      return ref.watch(
        searchRefreshControllerProvider.select((state) => state.session),
      );
    });

final Provider<SearchRefreshFeedbackState> searchRefreshFeedbackProvider =
    Provider<SearchRefreshFeedbackState>((ref) {
      return ref.watch(
        searchRefreshControllerProvider.select((state) => state.feedback),
      );
    });

final Provider<SearchPendingReindexHandoffState>
searchPendingReindexHandoffProvider =
    Provider<SearchPendingReindexHandoffState>((ref) {
      return ref.watch(
        searchRefreshControllerProvider.select((state) => state.handoff),
      );
    });
