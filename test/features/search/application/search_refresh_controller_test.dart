import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/application/search_index_use_cases.dart';
import 'package:note_secret_search/features/search/application/search_lock_guard.dart';
import 'package:note_secret_search/features/search/application/search_refresh_controller.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';

void main() {
  test(
    'refresh enters indexing immediately and ignores a duplicate operation',
    () async {
      final completion = Completer<SearchRefreshExecutionResult>();
      final runner = _ControlledRefreshRunner(completion);
      final controller = SearchRefreshController(
        refreshRunner: runner,
        indexRunner: const _NoopIndexRunner(),
        lockGuard: SearchLockGuard(accessAllowed: true),
      );
      addTearDown(controller.dispose);

      final first = controller.refresh('bank');

      expect(controller.state.phase, SearchRefreshPhase.indexing);
      expect(runner.calls, 1);
      expect(
        await controller.refresh('bank'),
        SearchRefreshExecutionResult.ignored,
      );

      completion.complete(SearchRefreshExecutionResult.completed);

      expect(await first, SearchRefreshExecutionResult.completed);
      expect(controller.state.phase, SearchRefreshPhase.idle);
    },
  );
}

class _ControlledRefreshRunner implements SearchRefreshRunner {
  _ControlledRefreshRunner(this._completion);

  final Completer<SearchRefreshExecutionResult> _completion;
  var calls = 0;

  @override
  Future<SearchRefreshExecutionResult> execute({
    required String query,
    required SearchIndexTaskState taskState,
    required SearchIndexTaskStateWriter onTaskState,
    required SearchRefreshPhaseWriter onReloading,
    required SearchRefreshFeedbackWriter onFeedback,
  }) {
    calls += 1;
    return _completion.future;
  }
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
