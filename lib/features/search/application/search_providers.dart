import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/application/search_service.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';

part 'search_index_controller.dart';

final sqliteEmbeddingRepositoryProvider = Provider<SqliteEmbeddingRepository>((
  ref,
) {
  return SqliteEmbeddingRepository(database: ref.watch(appDatabaseProvider));
});

final searchScopeConfigProvider = FutureProvider<SearchScopeConfig>((
  ref,
) async {
  final configuration = await ref.watch(searchConfigurationProvider.future);
  return SearchScopeConfig(
    includeTitle: configuration.includeTitle,
    includeSecretNote: configuration.includeSecretNote,
    includePasswordField: configuration.includePasswordField,
    includeUsername: configuration.includeUsername,
    includeUrl: configuration.includeUrl,
    includeTags: configuration.includeTags,
    includeNoteBody: configuration.includeNoteBody,
    allowLocalEmbedding: configuration.allowLocalEmbedding,
    allowExternalProviderAccess: configuration.allowExternalProviderAccess,
  );
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

final searchIndexStatusProvider = FutureProvider<SearchIndexStatus>((ref) {
  return guardSensitiveFuture<SearchIndexStatus>(
    ref,
    lockedValue: const SearchIndexStatus(
      engineReady: false,
      engineReason: '应用已锁定。',
      hasActiveEmbeddingModel: false,
      pendingItems: <SearchIndexPendingItem>[],
    ),
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
      final taskState = ref.watch(searchIndexTaskStateProvider);
      return SearchIndexStatus(
        engineReady: baseStatus.engineReady,
        engineReason: baseStatus.engineReason,
        hasActiveEmbeddingModel: baseStatus.hasActiveEmbeddingModel,
        pendingItems: baseStatus.pendingItems,
        pendingCount: baseStatus.pendingCount,
        taskState: taskState,
      );
    },
  );
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

final searchIndexControllerProvider = Provider<SearchIndexController>((ref) {
  return SearchIndexController(ref: ref);
});

final searchIndexTaskStateProvider = StateProvider<SearchIndexTaskState>(
  (ref) => const SearchIndexTaskState.idle(),
);

final searchRefreshSessionProvider = StateProvider<SearchRefreshSessionState>(
  (ref) => const SearchRefreshSessionState.idle(),
);

final searchRefreshFeedbackProvider = StateProvider<SearchRefreshFeedbackState>(
  (ref) => const SearchRefreshFeedbackState.hidden(),
);

final searchPendingReindexHandoffProvider =
    StateProvider<SearchPendingReindexHandoffState>(
      (ref) => const SearchPendingReindexHandoffState.hidden(),
    );

final searchScopeControllerProvider = Provider<SearchScopeController>((ref) {
  return SearchScopeController(ref: ref);
});

class SearchScopeController {
  SearchScopeController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> update(SearchScopeConfig config) async {
    _ref.read(searchIndexWriteFenceProvider).invalidate();
    final current = await _ref.read(searchConfigurationProvider.future);
    final repository = await _ref.read(
      searchConfigurationRepositoryProvider.future,
    );
    await repository.save(
      _configurationFromScope(current: current, scope: config),
    );
    invalidateSearchConfiguration(_ref);
  }
}

SearchConfiguration _configurationFromScope({
  required SearchConfiguration current,
  required SearchScopeConfig scope,
}) {
  return current.copyWith(
    includeTitle: scope.includeTitle,
    includeSecretNote: scope.includeSecretNote,
    includePasswordField: scope.includePasswordField,
    includeUsername: scope.includeUsername,
    includeUrl: scope.includeUrl,
    includeTags: scope.includeTags,
    includeNoteBody: scope.includeNoteBody,
    allowLocalEmbedding: scope.allowLocalEmbedding,
    allowExternalProviderAccess: scope.allowExternalProviderAccess,
  );
}
