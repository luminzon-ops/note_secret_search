import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/search/application/search_index_use_cases.dart';
import 'package:note_secret_search/features/search/application/search_lock_guard.dart';
import 'package:note_secret_search/features/search/application/search_refresh_state.dart';
import 'package:note_secret_search/features/search/application/search_settings_use_case.dart';

export 'search_refresh_state.dart';

class SearchRefreshController extends StateNotifier<SearchRefreshState> {
  SearchRefreshController({
    required SearchRefreshRunner refreshRunner,
    required SearchIndexRunner indexRunner,
    required SearchLockGuard lockGuard,
  }) : _refreshRunner = refreshRunner,
       _indexRunner = indexRunner,
       _lockGuard = lockGuard,
       super(const SearchRefreshState.idle());

  final SearchRefreshRunner _refreshRunner;
  final SearchIndexRunner _indexRunner;
  final SearchLockGuard _lockGuard;
  var _operationGeneration = 0;

  Future<SearchRefreshExecutionResult> refresh(String query) async {
    if (state.refreshing) {
      return SearchRefreshExecutionResult.ignored;
    }

    final generation = ++_operationGeneration;
    final lockEpoch = _lockGuard.epoch;
    state = state.copyWith(
      phase: SearchRefreshPhase.indexing,
      feedback: const SearchRefreshFeedbackState.hidden(),
    );

    try {
      final result = await _refreshRunner.execute(
        query: query.trim(),
        taskState: state.task,
        onTaskState: (taskState) {
          if (_isCurrent(generation, lockEpoch)) {
            state = state.copyWith(task: taskState);
          }
        },
        onReloading: () {
          if (_isCurrent(generation, lockEpoch)) {
            state = state.copyWith(phase: SearchRefreshPhase.reloading);
          }
        },
        onFeedback: (feedback) {
          if (_isCurrent(generation, lockEpoch)) {
            state = state.copyWith(feedback: feedback);
          }
        },
      );
      if (!_isCurrent(generation, lockEpoch)) {
        return SearchRefreshExecutionResult.locked;
      }
      if (result == SearchRefreshExecutionResult.completed) {
        state = state.copyWith(
          phase: SearchRefreshPhase.idle,
          handoff: const SearchPendingReindexHandoffState.hidden(),
          postSaveNeedsReindex: false,
          lastCompletedAt: _now(),
        );
      } else {
        state = state.copyWith(phase: SearchRefreshPhase.idle);
      }
      return result;
    } catch (_) {
      if (_isCurrent(generation, lockEpoch)) {
        state = state.copyWith(
          phase: SearchRefreshPhase.idle,
          feedback: const SearchRefreshFeedbackState.hidden(),
        );
      }
      rethrow;
    }
  }

  Future<SearchIndexExecutionResult> indexPendingOnly() async {
    if (state.refreshing) {
      return SearchIndexExecutionResult.skipped;
    }
    final generation = ++_operationGeneration;
    final lockEpoch = _lockGuard.epoch;
    state = state.copyWith(phase: SearchRefreshPhase.indexing);
    try {
      final result = await _indexRunner.execute(
        taskState: state.task,
        onTaskState: (taskState) {
          if (_isCurrent(generation, lockEpoch)) {
            state = state.copyWith(task: taskState);
          }
        },
      );
      if (_isCurrent(generation, lockEpoch)) {
        state = state.copyWith(phase: SearchRefreshPhase.idle);
      }
      return result;
    } catch (_) {
      if (_isCurrent(generation, lockEpoch)) {
        state = state.copyWith(phase: SearchRefreshPhase.idle);
      }
      rethrow;
    }
  }

  void resetForLock() {
    _operationGeneration += 1;
    state = const SearchRefreshState.idle();
  }

  void recordSettingsSaved(SearchSettingsSaveResult result) {
    state = state.copyWith(postSaveNeedsReindex: result.requiresReindex);
  }

  void clearPostSaveReindex() {
    state = state.copyWith(postSaveNeedsReindex: false);
  }

  void publishHandoff() {
    if (!state.postSaveNeedsReindex) {
      return;
    }
    state = state.copyWith(
      postSaveNeedsReindex: false,
      handoff: const SearchPendingReindexHandoffState(
        visible: true,
        message: '索引设置已保存。刷新搜索状态后，当前结果会使用新的语义索引配置。',
      ),
    );
  }

  bool _isCurrent(int generation, int lockEpoch) {
    return generation == _operationGeneration &&
        _lockGuard.permits(lockEpoch) &&
        mounted;
  }

  DateTime _now() => DateTime.now();
}
