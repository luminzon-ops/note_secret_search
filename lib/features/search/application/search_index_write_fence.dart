import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/search/domain/embedding_index_repository.dart';

final searchIndexWriteFenceProvider = Provider<SearchIndexWriteFence>((ref) {
  return SearchIndexWriteFence();
});

class SearchIndexWriteFence {
  int _revision = 0;

  int get revision => _revision;

  void invalidate() {
    _revision += 1;
  }

  void validate(int expectedRevision) {
    if (_revision != expectedRevision) {
      throw const EmbeddingIndexStaleWriteException();
    }
  }
}
