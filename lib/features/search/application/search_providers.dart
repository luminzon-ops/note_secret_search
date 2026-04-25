import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/application/search_service.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/infrastructure/shared_preferences_search_repository.dart';
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

  final readiness = await ref.watch(semanticSearchReadinessProvider.future);
  if (!readiness.ready || readiness.activeEmbeddingModel == null) {
    return const <SemanticSearchResult>[];
  }

  final scope = await ref.watch(searchScopeConfigProvider.future);
  final secrets = await ref.watch(secretListProvider.future);
  final notes = await ref.watch(noteListProvider.future);
  return ref.watch(semanticSearchServiceProvider).search(
        query: query,
        scope: scope,
        activeEmbeddingModel: readiness.activeEmbeddingModel!,
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

final searchRefreshSessionProvider = StateProvider<SearchRefreshSessionState>(
  (ref) => const SearchRefreshSessionState.idle(),
);

final searchRefreshFeedbackProvider = StateProvider<SearchRefreshFeedbackState>(
  (ref) => const SearchRefreshFeedbackState.hidden(),
);

final searchPendingReindexHandoffProvider = StateProvider<SearchPendingReindexHandoffState>(
  (ref) => const SearchPendingReindexHandoffState.hidden(),
);

class SearchRefreshSessionState {
  const SearchRefreshSessionState({
    required this.refreshing,
    this.message,
    this.lastCompletedAt,
  });

  const SearchRefreshSessionState.idle()
      : refreshing = false,
        message = null,
        lastCompletedAt = null;

  final bool refreshing;
  final String? message;
  final DateTime? lastCompletedAt;

  SearchRefreshSessionState copyWith({
    bool? refreshing,
    String? message,
    bool clearMessage = false,
    DateTime? lastCompletedAt,
    bool clearLastCompletedAt = false,
  }) {
    return SearchRefreshSessionState(
      refreshing: refreshing ?? this.refreshing,
      message: clearMessage ? null : (message ?? this.message),
      lastCompletedAt: clearLastCompletedAt ? null : (lastCompletedAt ?? this.lastCompletedAt),
    );
  }
}

class SearchRefreshFeedbackState {
  const SearchRefreshFeedbackState({
    required this.visible,
    this.headline,
    this.message,
    this.changed,
    this.queryAtRefresh,
    this.completedAt,
  });

  const SearchRefreshFeedbackState.hidden()
      : visible = false,
        headline = null,
        message = null,
        changed = null,
        queryAtRefresh = null,
        completedAt = null;

  final bool visible;
  final String? headline;
  final String? message;
  final bool? changed;
  final String? queryAtRefresh;
  final DateTime? completedAt;
}

class SearchPendingReindexHandoffState {
  const SearchPendingReindexHandoffState({required this.visible, this.message});

  const SearchPendingReindexHandoffState.hidden()
      : visible = false,
        message = null;

  final bool visible;
  final String? message;
}

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

  Future<void> indexPendingAndRefresh() async {
    final query = _ref.read(searchQueryProvider).trim();
    final beforeResults = await _ref.read(unifiedSearchResultsProvider.future);
    final beforeIds = beforeResults.map((item) => item.id).toList(growable: false);

    _ref.read(searchRefreshFeedbackProvider.notifier).state =
        const SearchRefreshFeedbackState.hidden();

    await indexPending();

    _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle()
        .copyWith(
          refreshing: true,
          message: '正在刷新搜索状态与结果...',
        );

    try {
      _ref.invalidate(searchIndexStatusProvider);
      _ref.invalidate(semanticSearchResultsProvider);
      _ref.invalidate(unifiedSearchResultsProvider);

      await _ref.read(searchIndexStatusProvider.future);
      await _ref.read(semanticSearchResultsProvider.future);
      final afterResults = await _ref.read(unifiedSearchResultsProvider.future);

      _ref.read(searchRefreshFeedbackProvider.notifier).state = _buildRefreshFeedback(
        query: query,
        beforeIds: beforeIds,
        afterIds: afterResults.map((item) => item.id).toList(growable: false),
      );

      _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle()
          .copyWith(lastCompletedAt: DateTime.now());
    } catch (_) {
      _ref.read(searchRefreshFeedbackProvider.notifier).state =
          const SearchRefreshFeedbackState.hidden();
      _ref.read(searchRefreshSessionProvider.notifier).state = const SearchRefreshSessionState.idle();
      rethrow;
    }
  }

  SearchRefreshFeedbackState _buildRefreshFeedback({
    required String query,
    required List<String> beforeIds,
    required List<String> afterIds,
  }) {
    final now = DateTime.now();
    if (query.isEmpty) {
      return SearchRefreshFeedbackState(
        visible: true,
        headline: '搜索状态已刷新',
        message: '输入关键词后可查看最新结果。',
        changed: null,
        queryAtRefresh: query,
        completedAt: now,
      );
    }

    final countChanged = beforeIds.length != afterIds.length;
    final orderChanged = !_sameOrderedIds(beforeIds, afterIds);

    if (countChanged) {
      return SearchRefreshFeedbackState(
        visible: true,
        headline: '搜索状态已刷新',
        message: '当前结果已更新，结果数量从 ${beforeIds.length} 条变为 ${afterIds.length} 条。',
        changed: true,
        queryAtRefresh: query,
        completedAt: now,
      );
    }

    if (orderChanged) {
      return SearchRefreshFeedbackState(
        visible: true,
        headline: '搜索状态已刷新',
        message: '当前结果已更新，本轮刷新调整了结果排序。',
        changed: true,
        queryAtRefresh: query,
        completedAt: now,
      );
    }

    return SearchRefreshFeedbackState(
      visible: true,
      headline: '搜索状态已刷新',
      message: '当前结果已更新，本轮刷新未改变当前结果。',
      changed: false,
      queryAtRefresh: query,
      completedAt: now,
    );
  }

  bool _sameOrderedIds(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
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
