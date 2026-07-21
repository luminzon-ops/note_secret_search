import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/semantic_search_service.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/application/search_service.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';

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

final searchFusionServiceProvider = Provider<SearchFusionService>((ref) {
  return const SearchFusionService();
});

final searchIndexServiceProvider = Provider<SearchIndexService>((ref) {
  return SearchIndexService(
    repository: ref.watch(sqliteEmbeddingRepositoryProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
    embeddingEngine: ref.watch(embeddingEngineProvider),
    sessionKeyStore: ref.watch(databaseSessionKeyStoreProvider),
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
      final secrets = await ref.watch(secretListProvider.future);
      final notes = await ref.watch(noteListProvider.future);
      return ref
          .watch(searchServiceProvider)
          .search(
            activeVaultId: vault.id,
            query: query,
            configuration: configuration,
            secrets: secrets,
            notes: notes,
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
      final secrets = await ref.watch(secretListProvider.future);
      final notes = await ref.watch(noteListProvider.future);
      final activeModel = await ref.watch(activeEmbeddingModelProvider.future);
      final configuration = await ref.watch(searchConfigurationProvider.future);
      final modelRevisionHash = activeModel == null
          ? ''
          : await ref.watch(
              searchIndexModelRevisionProvider(activeModel).future,
            );
      final baseStatus = await ref
          .watch(searchIndexServiceProvider)
          .buildStatus(
            secrets: secrets,
            notes: notes,
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
          final secrets = await ref.watch(secretListProvider.future);
          final notes = await ref.watch(noteListProvider.future);
          final modelRevisionHash = await ref.watch(
            searchIndexModelRevisionProvider(
              readiness.activeEmbeddingModel!,
            ).future,
          );
          return ref
              .watch(semanticSearchServiceProvider)
              .search(
                activeVaultId: vault.id,
                query: query,
                configuration: configuration,
                modelRevisionHash: modelRevisionHash,
                activeEmbeddingModel: readiness.activeEmbeddingModel!,
                secrets: secrets,
                notes: notes,
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
      lastCompletedAt: clearLastCompletedAt
          ? null
          : (lastCompletedAt ?? this.lastCompletedAt),
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
    final lockEpoch = _ref.read(lockSessionControllerProvider).lockEpoch;
    if (!_canContinue(lockEpoch)) {
      return;
    }

    final status = await _ref.read(searchIndexStatusProvider.future);
    if (!_canContinue(lockEpoch)) {
      return;
    }
    final activeModel = await _ref.read(activeEmbeddingModelProvider.future);
    if (!_canContinue(lockEpoch)) {
      return;
    }
    final configuration = await _ref.read(searchConfigurationProvider.future);
    if (!_canContinue(lockEpoch)) {
      return;
    }
    if (!status.readyForIndexing || activeModel == null) {
      return;
    }

    if (!_canContinue(lockEpoch)) {
      return;
    }
    _ref.read(searchIndexTaskStateProvider.notifier).state = status.taskState
        .copyWith(running: true, clearLastError: true);

    try {
      final modelRevisionHash = await _ref.read(
        searchIndexModelRevisionProvider(activeModel).future,
      );
      if (!_canContinue(lockEpoch)) {
        return;
      }
      await _ref
          .read(searchIndexServiceProvider)
          .indexPendingItems(
            items: status.pendingItems,
            activeEmbeddingModel: activeModel,
            modelRevisionHash: modelRevisionHash,
            configuration: configuration,
          );

      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref
          .read(searchIndexTaskStateProvider.notifier)
          .state = const SearchIndexTaskState.idle().copyWith(
        lastCompletedAt: DateTime.now(),
        lastIndexedCount: status.pendingItems.length,
      );
      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref.invalidate(searchIndexStatusProvider);
    } catch (error) {
      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref
          .read(searchIndexTaskStateProvider.notifier)
          .state = const SearchIndexTaskState.idle().copyWith(
        lastCompletedAt: DateTime.now(),
        lastIndexedCount: 0,
        lastError: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> indexPendingAndRefresh() async {
    final lockEpoch = _ref.read(lockSessionControllerProvider).lockEpoch;
    if (!_canContinue(lockEpoch)) {
      return;
    }

    final query = _ref.read(searchQueryProvider).trim();
    final beforeResults = await _ref.read(unifiedSearchResultsProvider.future);
    if (!_canContinue(lockEpoch)) {
      return;
    }
    final beforeIdentities = beforeResults
        .map((item) => item.identity)
        .toList(growable: false);

    if (!_canContinue(lockEpoch)) {
      return;
    }
    _ref.read(searchRefreshFeedbackProvider.notifier).state =
        const SearchRefreshFeedbackState.hidden();

    await indexPending();
    if (!_canContinue(lockEpoch)) {
      return;
    }

    _ref
        .read(searchRefreshSessionProvider.notifier)
        .state = const SearchRefreshSessionState.idle().copyWith(
      refreshing: true,
      message: '正在刷新搜索状态与结果...',
    );

    try {
      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref.invalidate(searchIndexStatusProvider);
      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref.invalidate(semanticSearchResultsProvider);
      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref.invalidate(unifiedSearchResultsProvider);

      await _ref.read(searchIndexStatusProvider.future);
      if (!_canContinue(lockEpoch)) {
        return;
      }
      await _ref.read(semanticSearchResultsProvider.future);
      if (!_canContinue(lockEpoch)) {
        return;
      }
      final afterResults = await _ref.read(unifiedSearchResultsProvider.future);
      if (!_canContinue(lockEpoch)) {
        return;
      }

      _ref
          .read(searchRefreshFeedbackProvider.notifier)
          .state = _buildRefreshFeedback(
        query: query,
        beforeIdentities: beforeIdentities,
        afterIdentities: afterResults
            .map((item) => item.identity)
            .toList(growable: false),
      );

      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref
          .read(searchRefreshSessionProvider.notifier)
          .state = const SearchRefreshSessionState.idle().copyWith(
        lastCompletedAt: DateTime.now(),
      );
    } catch (_) {
      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref.read(searchRefreshFeedbackProvider.notifier).state =
          const SearchRefreshFeedbackState.hidden();
      if (!_canContinue(lockEpoch)) {
        return;
      }
      _ref.read(searchRefreshSessionProvider.notifier).state =
          const SearchRefreshSessionState.idle();
      rethrow;
    }
  }

  bool _canContinue(int lockEpoch) {
    return _ref.read(lockSessionControllerProvider).lockEpoch == lockEpoch &&
        _ref.read(sensitiveStateAccessAllowedProvider);
  }

  SearchRefreshFeedbackState _buildRefreshFeedback({
    required String query,
    required List<SearchResultIdentity> beforeIdentities,
    required List<SearchResultIdentity> afterIdentities,
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

    final countChanged = beforeIdentities.length != afterIdentities.length;
    final orderChanged = !_sameOrderedIdentities(
      beforeIdentities,
      afterIdentities,
    );

    if (countChanged) {
      return SearchRefreshFeedbackState(
        visible: true,
        headline: '搜索状态已刷新',
        message:
            '当前结果已更新，结果数量从 ${beforeIdentities.length} 条变为 ${afterIdentities.length} 条。',
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

  bool _sameOrderedIdentities(
    List<SearchResultIdentity> left,
    List<SearchResultIdentity> right,
  ) {
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
