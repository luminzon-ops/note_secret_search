import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';

void main() {
  test('invalidate cancels active write leases', () {
    final fence = SearchIndexWriteFence();
    final lease = fence.acquireLease();
    var cancellationCallbacks = 0;
    lease.cancellationToken.register(() {
      cancellationCallbacks += 1;
    });

    fence.invalidate();

    expect(lease.cancellationToken.isCancelled, isTrue);
    expect(cancellationCallbacks, 1);
    expect(() => lease.validate(), throwsA(isA<Exception>()));
  });

  test('released write leases are not retained or cancelled', () {
    final fence = SearchIndexWriteFence();
    final lease = fence.acquireLease();
    var cancellationCallbacks = 0;
    lease.cancellationToken.register(() {
      cancellationCallbacks += 1;
    });

    lease.release();
    fence.invalidate();

    expect(lease.cancellationToken.isCancelled, isFalse);
    expect(cancellationCallbacks, 0);
  });
}
