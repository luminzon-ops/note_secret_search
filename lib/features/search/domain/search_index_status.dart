import 'dart:typed_data';

import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_index_document.dart';

class SearchIndexPendingItem {
  SearchIndexPendingItem({
    required this.sourceId,
    required this.sourceType,
    required this.title,
    required this.updatedAt,
    this.document,
    List<int>? sourceFingerprint,
    this.configurationEpoch,
    this.modelRevisionHash,
    this.plainTextHash = '',
    this.indexPlainText = '',
  }) : sourceFingerprint = sourceFingerprint == null
           ? null
           : Uint8List.fromList(sourceFingerprint);

  final String sourceId;
  final SearchSourceType sourceType;
  final String title;
  final DateTime updatedAt;
  final SearchIndexDocument? document;
  final Uint8List? sourceFingerprint;
  final int? configurationEpoch;
  final String? modelRevisionHash;

  @Deprecated('Legacy Phase 3 test fixture field.')
  final String plainTextHash;

  @Deprecated('Legacy Phase 3 test fixture field.')
  final String indexPlainText;
}

class SearchIndexStatus {
  const SearchIndexStatus({
    required this.engineReady,
    required this.engineReason,
    required this.hasActiveEmbeddingModel,
    required this.pendingItems,
    this.taskState = const SearchIndexTaskState.idle(),
  });

  final bool engineReady;
  final String engineReason;
  final bool hasActiveEmbeddingModel;
  final List<SearchIndexPendingItem> pendingItems;
  final SearchIndexTaskState taskState;

  bool get readyForIndexing => engineReady && hasActiveEmbeddingModel;
}

class SearchIndexTaskState {
  const SearchIndexTaskState({
    required this.running,
    required this.lastCompletedAt,
    required this.lastIndexedCount,
    required this.lastError,
  });

  const SearchIndexTaskState.idle()
    : running = false,
      lastCompletedAt = null,
      lastIndexedCount = 0,
      lastError = null;

  final bool running;
  final DateTime? lastCompletedAt;
  final int lastIndexedCount;
  final String? lastError;

  SearchIndexTaskState copyWith({
    bool? running,
    DateTime? lastCompletedAt,
    bool clearLastCompletedAt = false,
    int? lastIndexedCount,
    String? lastError,
    bool clearLastError = false,
  }) {
    return SearchIndexTaskState(
      running: running ?? this.running,
      lastCompletedAt: clearLastCompletedAt
          ? null
          : (lastCompletedAt ?? this.lastCompletedAt),
      lastIndexedCount: lastIndexedCount ?? this.lastIndexedCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}
