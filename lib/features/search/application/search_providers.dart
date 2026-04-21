import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/application/search_service.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/infrastructure/shared_preferences_search_repository.dart';
import 'package:note_secret_search/features/search/infrastructure/placeholder_embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';

final sqliteEmbeddingRepositoryProvider = Provider<SqliteEmbeddingRepository>((ref) {
  return SqliteEmbeddingRepository(database: ref.watch(appDatabaseProvider));
});

final searchRepositoryProvider = FutureProvider<SearchRepository>((ref) async {
  final preferences = await ref.watch(sharedPreferencesProvider.future);
  return SharedPreferencesSearchRepository(
    preferences: preferences,
    embeddingRepository: ref.watch(sqliteEmbeddingRepositoryProvider),
  );
});

final searchScopeConfigProvider = FutureProvider<SearchScopeConfig>((ref) async {
  final repository = await ref.watch(searchRepositoryProvider.future);
  return repository.loadScopeConfig();
});

final searchServiceProvider = Provider<SearchService>((ref) {
  return SearchService(cryptoService: ref.watch(cryptoServiceProvider));
});

final searchFusionServiceProvider = Provider<SearchFusionService>((ref) {
  return const SearchFusionService();
});

final embeddingEngineProvider = Provider<EmbeddingEngine>((ref) {
  return const PlaceholderEmbeddingEngine();
});

final searchIndexServiceProvider = Provider<SearchIndexService>((ref) {
  return SearchIndexService(
    repository: ref.watch(searchRepositoryProvider).value!,
    cryptoService: ref.watch(cryptoServiceProvider),
    embeddingEngine: ref.watch(embeddingEngineProvider),
  );
});

final semanticSearchServiceProvider = Provider<SemanticSearchService>((ref) {
  return SemanticSearchService(
    repository: ref.watch(searchRepositoryProvider).value!,
    embeddingEngine: ref.watch(embeddingEngineProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
  );
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final keywordSearchResultsProvider = FutureProvider<List<SearchResultItem>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) {
    return const <SearchResultItem>[];
  }

  final scope = await ref.watch(searchScopeConfigProvider.future);
  final secrets = await ref.watch(secretListProvider.future);
  final notes = await ref.watch(noteListProvider.future);
  return ref.watch(searchServiceProvider).search(
        query: query,
        scope: scope,
        secrets: secrets,
        notes: notes,
      );
});

final searchIndexStatusProvider = FutureProvider<SearchIndexStatus>((ref) async {
  final secrets = await ref.watch(secretListProvider.future);
  final notes = await ref.watch(noteListProvider.future);
  final activeModel = await ref.watch(activeEmbeddingModelProvider.future);
  final settings = await ref.watch(searchIndexSettingsProvider.future);
  final baseStatus = await ref.watch(searchIndexServiceProvider).buildStatus(
        secrets: secrets,
        notes: notes,
        activeEmbeddingModel: activeModel,
        settings: settings,
      );
  final taskState = ref.watch(searchIndexTaskStateProvider);
  return SearchIndexStatus(
    engineReady: baseStatus.engineReady,
    engineReason: baseStatus.engineReason,
    hasActiveEmbeddingModel: baseStatus.hasActiveEmbeddingModel,
    pendingItems: baseStatus.pendingItems,
    taskState: taskState,
  );
});

final semanticSearchResultsProvider = FutureProvider<List<SemanticSearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) {
    return const <SemanticSearchResult>[];
  }

  final scope = await ref.watch(searchScopeConfigProvider.future);
  final activeModel = await ref.watch(activeEmbeddingModelProvider.future);
  if (activeModel == null) {
    return const <SemanticSearchResult>[];
  }

  final secrets = await ref.watch(secretListProvider.future);
  final notes = await ref.watch(noteListProvider.future);
  return ref.watch(semanticSearchServiceProvider).search(
        query: query,
        scope: scope,
        activeEmbeddingModel: activeModel,
        secrets: secrets,
        notes: notes,
      );
});

final unifiedSearchResultsProvider = FutureProvider<List<SearchResultItem>>((ref) async {
  final keywordResults = await ref.watch(keywordSearchResultsProvider.future);
  final semanticResults = await ref.watch(semanticSearchResultsProvider.future);
  return ref.watch(searchFusionServiceProvider).fuse(
        keywordResults: keywordResults,
        semanticResults: semanticResults,
      );
});

final searchIndexControllerProvider = Provider<SearchIndexController>((ref) {
  return SearchIndexController(ref: ref);
});

final searchIndexTaskStateProvider = StateProvider<SearchIndexTaskState>(
  (ref) => const SearchIndexTaskState.idle(),
);

class SearchIndexController {
  SearchIndexController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> indexPending() async {
    final status = await _ref.read(searchIndexStatusProvider.future);
    final activeModel = await _ref.read(activeEmbeddingModelProvider.future);
    final settings = await _ref.read(searchIndexSettingsProvider.future);
    if (!status.readyForIndexing || activeModel == null) {
      return;
    }

    _ref.read(searchIndexTaskStateProvider.notifier).state = status.taskState.copyWith(
          running: true,
          clearLastError: true,
        );

    try {
      await _ref.read(searchIndexServiceProvider).indexPendingItems(
            items: status.pendingItems,
            activeEmbeddingModel: activeModel,
            settings: settings,
          );

      _ref.read(searchIndexTaskStateProvider.notifier).state = const SearchIndexTaskState.idle()
          .copyWith(
            lastCompletedAt: DateTime.now(),
            lastIndexedCount: status.pendingItems.length,
          );
      _ref.invalidate(searchIndexStatusProvider);
    } catch (error) {
      _ref.read(searchIndexTaskStateProvider.notifier).state = const SearchIndexTaskState.idle()
          .copyWith(
            lastCompletedAt: DateTime.now(),
            lastIndexedCount: 0,
            lastError: error.toString(),
          );
      rethrow;
    }
  }
}

final searchScopeControllerProvider = Provider<SearchScopeController>((ref) {
  return SearchScopeController(ref: ref);
});

class SearchScopeController {
  SearchScopeController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> update(SearchScopeConfig config) async {
    final repository = await _ref.read(searchRepositoryProvider.future);
    await repository.saveScopeConfig(config);
    _ref.invalidate(searchScopeConfigProvider);
    _ref.invalidate(keywordSearchResultsProvider);
    _ref.invalidate(semanticSearchResultsProvider);
    _ref.invalidate(unifiedSearchResultsProvider);
    _ref.invalidate(semanticSearchReadinessProvider);
    _ref.invalidate(searchIndexStatusProvider);
  }
}
