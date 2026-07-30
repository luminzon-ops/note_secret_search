import 'package:note_secret_search/features/search/domain/search_index_status.dart';

enum SearchRefreshPhase { idle, indexing, reloading }

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

class SearchRefreshState {
  const SearchRefreshState({
    required this.phase,
    required this.task,
    required this.feedback,
    required this.handoff,
    required this.postSaveNeedsReindex,
    this.lastCompletedAt,
  });

  const SearchRefreshState.idle()
    : phase = SearchRefreshPhase.idle,
      task = const SearchIndexTaskState.idle(),
      feedback = const SearchRefreshFeedbackState.hidden(),
      handoff = const SearchPendingReindexHandoffState.hidden(),
      postSaveNeedsReindex = false,
      lastCompletedAt = null;

  final SearchRefreshPhase phase;
  final SearchIndexTaskState task;
  final SearchRefreshFeedbackState feedback;
  final SearchPendingReindexHandoffState handoff;
  final bool postSaveNeedsReindex;
  final DateTime? lastCompletedAt;

  bool get refreshing => phase != SearchRefreshPhase.idle;

  SearchRefreshSessionState get session {
    final message = switch (phase) {
      SearchRefreshPhase.idle => null,
      SearchRefreshPhase.indexing => '正在处理待索引内容...',
      SearchRefreshPhase.reloading => '正在刷新搜索状态与结果...',
    };
    return SearchRefreshSessionState(
      refreshing: refreshing,
      message: message,
      lastCompletedAt: lastCompletedAt,
    );
  }

  SearchRefreshState copyWith({
    SearchRefreshPhase? phase,
    SearchIndexTaskState? task,
    SearchRefreshFeedbackState? feedback,
    SearchPendingReindexHandoffState? handoff,
    bool? postSaveNeedsReindex,
    DateTime? lastCompletedAt,
    bool clearLastCompletedAt = false,
  }) {
    return SearchRefreshState(
      phase: phase ?? this.phase,
      task: task ?? this.task,
      feedback: feedback ?? this.feedback,
      handoff: handoff ?? this.handoff,
      postSaveNeedsReindex: postSaveNeedsReindex ?? this.postSaveNeedsReindex,
      lastCompletedAt: clearLastCompletedAt
          ? null
          : (lastCompletedAt ?? this.lastCompletedAt),
    );
  }
}
