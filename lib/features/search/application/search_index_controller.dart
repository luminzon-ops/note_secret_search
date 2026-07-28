part of 'search_providers.dart';

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
    final lockEpoch = _ref.read(searchLockGuardProvider).epoch;
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
    final activeVault = await _ref.read(defaultVaultProvider.future);
    if (!_canContinue(lockEpoch)) {
      return;
    }
    if (!status.readyForIndexing ||
        activeModel == null ||
        activeVault == null) {
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
      final indexedCount = await _ref
          .read(searchIndexServiceProvider)
          .indexCorpusPending(
            activeVaultId: activeVault.id,
            corpus: _ref.read(searchCorpusReaderProvider),
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
        lastIndexedCount: indexedCount,
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
    final lockEpoch = _ref.read(searchLockGuardProvider).epoch;
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
    final guard = _ref.read(searchLockGuardProvider);
    return guard.epoch == lockEpoch && guard.accessAllowed;
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
