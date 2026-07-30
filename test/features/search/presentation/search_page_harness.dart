part of 'search_page_test.dart';

class _RecordingSearchRefreshRunner implements SearchRefreshRunner {
  _RecordingSearchRefreshRunner({this.error});

  int refreshCalls = 0;
  final Object? error;

  @override
  Future<SearchRefreshExecutionResult> execute({
    required String query,
    required SearchIndexTaskState taskState,
    required SearchIndexTaskStateWriter onTaskState,
    required SearchRefreshPhaseWriter onReloading,
    required SearchRefreshFeedbackWriter onFeedback,
  }) async {
    refreshCalls++;
    if (error != null) {
      throw error!;
    }
    return SearchRefreshExecutionResult.completed;
  }
}

SearchRefreshController _handoffRefreshController(
  _RecordingSearchRefreshRunner runner,
) {
  return SearchRefreshController(
      refreshRunner: runner,
      indexRunner: const _NoopIndexRunner(),
      lockGuard: SearchLockGuard(accessAllowed: true),
    )
    ..recordSettingsSaved(
      SearchSettingsSaveResult(
        savedConfiguration: SearchConfiguration.defaults(),
        requiresReindex: true,
      ),
    )
    ..publishHandoff();
}

class _NoopIndexRunner implements SearchIndexRunner {
  const _NoopIndexRunner();

  @override
  Future<SearchIndexExecutionResult> execute({
    required SearchIndexTaskState taskState,
    required SearchIndexTaskStateWriter onTaskState,
  }) async {
    return SearchIndexExecutionResult.skipped;
  }
}
