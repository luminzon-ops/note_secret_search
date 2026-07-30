import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_service.dart';
import 'package:note_secret_search/features/search/application/search_lock_guard.dart';
import 'package:note_secret_search/features/search/application/search_refresh_state.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';

typedef SearchIndexTaskStateWriter = void Function(SearchIndexTaskState state);
typedef SearchRefreshPhaseWriter = void Function();
typedef SearchRefreshFeedbackWriter =
    void Function(SearchRefreshFeedbackState feedback);

enum SearchIndexExecutionResult { completed, skipped, locked }

enum SearchRefreshExecutionResult { completed, locked, ignored }

abstract interface class SearchIndexRunner {
  Future<SearchIndexExecutionResult> execute({
    required SearchIndexTaskState taskState,
    required SearchIndexTaskStateWriter onTaskState,
  });
}

abstract interface class SearchRefreshRunner {
  Future<SearchRefreshExecutionResult> execute({
    required String query,
    required SearchIndexTaskState taskState,
    required SearchIndexTaskStateWriter onTaskState,
    required SearchRefreshPhaseWriter onReloading,
    required SearchRefreshFeedbackWriter onFeedback,
  });
}

class IndexPendingSearchUseCase implements SearchIndexRunner {
  const IndexPendingSearchUseCase({
    required SearchLockGuard lockGuard,
    required Future<SearchIndexStatus> Function() loadIndexStatus,
    required Future<ModelRegistryEntry?> Function() loadActiveEmbeddingModel,
    required Future<SearchConfiguration> Function() loadConfiguration,
    required Future<Vault?> Function() loadDefaultVault,
    required Future<String> Function(ModelRegistryEntry model)
    loadModelRevisionHash,
    required SearchCorpusReader Function() loadCorpusReader,
    required SearchIndexService Function() loadIndexService,
    required void Function() invalidateIndexStatus,
    DateTime Function()? clock,
  }) : _lockGuard = lockGuard,
       _loadIndexStatus = loadIndexStatus,
       _loadActiveEmbeddingModel = loadActiveEmbeddingModel,
       _loadConfiguration = loadConfiguration,
       _loadDefaultVault = loadDefaultVault,
       _loadModelRevisionHash = loadModelRevisionHash,
       _loadCorpusReader = loadCorpusReader,
       _loadIndexService = loadIndexService,
       _invalidateIndexStatus = invalidateIndexStatus,
       _clock = clock ?? DateTime.now;

  final SearchLockGuard _lockGuard;
  final Future<SearchIndexStatus> Function() _loadIndexStatus;
  final Future<ModelRegistryEntry?> Function() _loadActiveEmbeddingModel;
  final Future<SearchConfiguration> Function() _loadConfiguration;
  final Future<Vault?> Function() _loadDefaultVault;
  final Future<String> Function(ModelRegistryEntry model)
  _loadModelRevisionHash;
  final SearchCorpusReader Function() _loadCorpusReader;
  final SearchIndexService Function() _loadIndexService;
  final void Function() _invalidateIndexStatus;
  final DateTime Function() _clock;

  @override
  Future<SearchIndexExecutionResult> execute({
    required SearchIndexTaskState taskState,
    required SearchIndexTaskStateWriter onTaskState,
  }) async {
    final lockEpoch = _lockGuard.epoch;
    if (!_canContinue(lockEpoch)) {
      return SearchIndexExecutionResult.locked;
    }

    final status = await _loadIndexStatus();
    if (!_canContinue(lockEpoch)) {
      return SearchIndexExecutionResult.locked;
    }
    final activeModel = await _loadActiveEmbeddingModel();
    if (!_canContinue(lockEpoch)) {
      return SearchIndexExecutionResult.locked;
    }
    final configuration = await _loadConfiguration();
    if (!_canContinue(lockEpoch)) {
      return SearchIndexExecutionResult.locked;
    }
    final activeVault = await _loadDefaultVault();
    if (!_canContinue(lockEpoch)) {
      return SearchIndexExecutionResult.locked;
    }
    if (!status.readyForIndexing ||
        activeModel == null ||
        activeVault == null) {
      return SearchIndexExecutionResult.skipped;
    }

    onTaskState(status.taskState.copyWith(running: true, clearLastError: true));

    try {
      final modelRevisionHash = await _loadModelRevisionHash(activeModel);
      if (!_canContinue(lockEpoch)) {
        return SearchIndexExecutionResult.locked;
      }
      final indexedCount = await _loadIndexService().indexCorpusPending(
        activeVaultId: activeVault.id,
        corpus: _loadCorpusReader(),
        activeEmbeddingModel: activeModel,
        modelRevisionHash: modelRevisionHash,
        configuration: configuration,
      );
      if (!_canContinue(lockEpoch)) {
        return SearchIndexExecutionResult.locked;
      }
      onTaskState(
        const SearchIndexTaskState.idle().copyWith(
          lastCompletedAt: _clock(),
          lastIndexedCount: indexedCount,
        ),
      );
      if (!_canContinue(lockEpoch)) {
        return SearchIndexExecutionResult.locked;
      }
      _invalidateIndexStatus();
      return SearchIndexExecutionResult.completed;
    } catch (error) {
      if (!_canContinue(lockEpoch)) {
        return SearchIndexExecutionResult.locked;
      }
      onTaskState(
        const SearchIndexTaskState.idle().copyWith(
          lastCompletedAt: _clock(),
          lastIndexedCount: 0,
          lastError: error.toString(),
        ),
      );
      rethrow;
    }
  }

  bool _canContinue(int lockEpoch) {
    return _lockGuard.permits(lockEpoch);
  }
}

class RefreshSearchIndexUseCase implements SearchRefreshRunner {
  const RefreshSearchIndexUseCase({
    required SearchLockGuard lockGuard,
    required SearchIndexRunner indexRunner,
    required Future<List<SearchResultItem>> Function() loadUnifiedResults,
    required void Function() invalidateIndexStatus,
    required void Function() invalidateSemanticResults,
    required void Function() invalidateUnifiedResults,
    required Future<SearchIndexStatus> Function() awaitIndexStatus,
    required Future<void> Function() awaitSemanticResults,
    required Future<List<SearchResultItem>> Function() awaitUnifiedResults,
    DateTime Function()? clock,
  }) : _lockGuard = lockGuard,
       _indexRunner = indexRunner,
       _loadUnifiedResults = loadUnifiedResults,
       _invalidateIndexStatus = invalidateIndexStatus,
       _invalidateSemanticResults = invalidateSemanticResults,
       _invalidateUnifiedResults = invalidateUnifiedResults,
       _awaitIndexStatus = awaitIndexStatus,
       _awaitSemanticResults = awaitSemanticResults,
       _awaitUnifiedResults = awaitUnifiedResults,
       _clock = clock ?? DateTime.now;

  final SearchLockGuard _lockGuard;
  final SearchIndexRunner _indexRunner;
  final Future<List<SearchResultItem>> Function() _loadUnifiedResults;
  final void Function() _invalidateIndexStatus;
  final void Function() _invalidateSemanticResults;
  final void Function() _invalidateUnifiedResults;
  final Future<SearchIndexStatus> Function() _awaitIndexStatus;
  final Future<void> Function() _awaitSemanticResults;
  final Future<List<SearchResultItem>> Function() _awaitUnifiedResults;
  final DateTime Function() _clock;

  @override
  Future<SearchRefreshExecutionResult> execute({
    required String query,
    required SearchIndexTaskState taskState,
    required SearchIndexTaskStateWriter onTaskState,
    required SearchRefreshPhaseWriter onReloading,
    required SearchRefreshFeedbackWriter onFeedback,
  }) async {
    final lockEpoch = _lockGuard.epoch;
    if (!_canContinue(lockEpoch)) {
      return SearchRefreshExecutionResult.locked;
    }

    final beforeResults = await _loadUnifiedResults();
    if (!_canContinue(lockEpoch)) {
      return SearchRefreshExecutionResult.locked;
    }
    final beforeIdentities = beforeResults
        .map((item) => item.identity)
        .toList(growable: false);

    final indexResult = await _indexRunner.execute(
      taskState: taskState,
      onTaskState: onTaskState,
    );
    if (!_canContinue(lockEpoch) ||
        indexResult == SearchIndexExecutionResult.locked) {
      return SearchRefreshExecutionResult.locked;
    }

    onReloading();
    _invalidateIndexStatus();
    if (!_canContinue(lockEpoch)) {
      return SearchRefreshExecutionResult.locked;
    }
    _invalidateSemanticResults();
    if (!_canContinue(lockEpoch)) {
      return SearchRefreshExecutionResult.locked;
    }
    _invalidateUnifiedResults();

    await _awaitIndexStatus();
    if (!_canContinue(lockEpoch)) {
      return SearchRefreshExecutionResult.locked;
    }
    await _awaitSemanticResults();
    if (!_canContinue(lockEpoch)) {
      return SearchRefreshExecutionResult.locked;
    }
    final afterResults = await _awaitUnifiedResults();
    if (!_canContinue(lockEpoch)) {
      return SearchRefreshExecutionResult.locked;
    }

    onFeedback(
      _buildRefreshFeedback(
        query: query,
        beforeIdentities: beforeIdentities,
        afterIdentities: afterResults
            .map((item) => item.identity)
            .toList(growable: false),
      ),
    );
    return SearchRefreshExecutionResult.completed;
  }

  bool _canContinue(int lockEpoch) {
    return _lockGuard.permits(lockEpoch);
  }

  SearchRefreshFeedbackState _buildRefreshFeedback({
    required String query,
    required List<SearchResultIdentity> beforeIdentities,
    required List<SearchResultIdentity> afterIdentities,
  }) {
    final now = _clock();
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
