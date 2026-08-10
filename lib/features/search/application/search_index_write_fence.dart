import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';

final searchIndexWriteFenceProvider = Provider<SearchIndexWriteFence>((ref) {
  return SearchIndexWriteFence();
});

class SearchIndexWriteFence {
  int _revision = 0;
  final Set<SearchIndexWriteLease> _leases = <SearchIndexWriteLease>{};

  int get revision => _revision;

  void invalidate() {
    _revision += 1;
    final leases = _leases.toList(growable: false);
    _leases.clear();
    for (final lease in leases) {
      lease._cancel();
    }
  }

  void validate(int expectedRevision) {
    if (_revision != expectedRevision) {
      throw const EmbeddingIndexStaleWriteException();
    }
  }

  SearchIndexWriteLease acquireLease() {
    final lease = SearchIndexWriteLease._(this, _revision);
    _leases.add(lease);
    return lease;
  }

  void _release(SearchIndexWriteLease lease) {
    _leases.remove(lease);
  }
}

class SearchIndexWriteLease {
  SearchIndexWriteLease._(this._fence, this._revision);

  final SearchIndexWriteFence _fence;
  final int _revision;
  final EmbeddingCancellationController _cancellation =
      EmbeddingCancellationController();
  bool _released = false;

  EmbeddingCancellationToken get cancellationToken => _cancellation;

  void validate() {
    _fence.validate(_revision);
  }

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _fence._release(this);
  }

  void _cancel() {
    if (!_released) {
      _cancellation.cancel();
    }
  }
}
