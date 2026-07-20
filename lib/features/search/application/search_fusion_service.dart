import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

class SearchFusionService {
  const SearchFusionService();

  List<SearchResultItem> fuse({
    required List<SearchResultItem> keywordResults,
    required List<SemanticSearchResult> semanticResults,
    String query = '',
  }) {
    final byKey = <String, SearchResultItem>{};
    for (final item in keywordResults) {
      byKey[_keyFor(item)] = item.copyWith(
        matchSources: <SearchMatchSource>{
          ...item.matchSources,
          SearchMatchSource.keyword,
        },
      );
    }
    for (final semantic in semanticResults) {
      final key = _keyFor(semantic.item);
      final existing = byKey[key];
      final incomingWins =
          existing?.semanticScore == null ||
          semantic.score > existing!.semanticScore!;
      final semanticFields = incomingWins
          ? (
              score: semantic.score,
              raw: semantic.primaryRawSimilarity,
              summary: semantic.hitSummary,
              field: semantic.hitField,
              affinity: semantic.queryAffinity,
              quality: semantic.fieldQualityTier,
            )
          : (
              score: existing.semanticScore!,
              raw: existing.semanticRawSimilarity,
              summary: existing.semanticHitSummary!,
              field: existing.semanticHitField!,
              affinity: existing.semanticQueryAffinity,
              quality: existing.semanticFieldQualityTier,
            );
      final base = existing ?? semantic.item;
      byKey[key] = base.copyWith(
        matchSources: existing == null
            ? const <SearchMatchSource>{SearchMatchSource.semantic}
            : <SearchMatchSource>{
                ...base.matchSources,
                SearchMatchSource.semantic,
              },
        semanticScore: semanticFields.score,
        semanticRawSimilarity: semanticFields.raw,
        semanticHitSummary: semanticFields.summary,
        semanticHitField: semanticFields.field,
        semanticQueryAffinity: semanticFields.affinity,
        semanticFieldQualityTier: semanticFields.quality,
      );
    }

    final results = byKey.values
        .where(_shouldKeepUnifiedResult)
        .toList(growable: false);
    results.sort((left, right) => _compare(query, left, right));
    return List<SearchResultItem>.unmodifiable(results.take(100));
  }

  int _compare(String query, SearchResultItem left, SearchResultItem right) {
    var result = _sourcePriority(
      right.matchSources,
    ).compareTo(_sourcePriority(left.matchSources));
    result = result != 0
        ? result
        : _queryAffinity(query, right).compareTo(_queryAffinity(query, left));
    result = result != 0
        ? result
        : _qualityTier(right).compareTo(_qualityTier(left));
    result = result != 0
        ? result
        : (right.semanticScore ?? -1).compareTo(left.semanticScore ?? -1);
    result = result != 0
        ? result
        : _fieldPriority(right).compareTo(_fieldPriority(left));
    result = result != 0
        ? result
        : (right.favorite ? 1 : 0).compareTo(left.favorite ? 1 : 0);
    result = result != 0 ? result : right.updatedAt.compareTo(left.updatedAt);
    result = result != 0 ? result : left.type.index.compareTo(right.type.index);
    return result != 0 ? result : left.id.compareTo(right.id);
  }

  int _queryAffinity(String query, SearchResultItem item) {
    if (item.semanticQueryAffinity != 0) {
      return item.semanticQueryAffinity;
    }
    final normalized = query.trim();
    if (normalized.contains('@') &&
        item.keywordHitFields.contains(SearchSourceField.secretUsername)) {
      return 1;
    }
    if ((normalized.contains('://') ||
            normalized.contains('.') ||
            normalized.contains('/')) &&
        item.keywordHitFields.contains(SearchSourceField.secretWebsiteUrl)) {
      return 1;
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{1,24}$').hasMatch(normalized) &&
        item.keywordHitFields.any(
          (field) =>
              field == SearchSourceField.secretTags ||
              field == SearchSourceField.noteTags,
        )) {
      return 1;
    }
    return 0;
  }

  int _qualityTier(SearchResultItem item) {
    if (item.semanticFieldQualityTier != 0) {
      return item.semanticFieldQualityTier;
    }
    return switch (item.semanticHitField) {
      SemanticHitField.title ||
      SemanticHitField.username ||
      SemanticHitField.summary => 2,
      SemanticHitField.url ||
      SemanticHitField.secretNote ||
      SemanticHitField.tags ||
      SemanticHitField.noteBody => 1,
      null => item.keywordHitFields.any(_isHighValueKeywordField) ? 2 : 1,
    };
  }

  bool _isHighValueKeywordField(SearchSourceField field) {
    return field == SearchSourceField.secretTitle ||
        field == SearchSourceField.noteTitle ||
        field == SearchSourceField.secretUsername ||
        field == SearchSourceField.noteSummary;
  }

  int _fieldPriority(SearchResultItem item) {
    final semantic = switch (item.semanticHitField) {
      SemanticHitField.title => 6,
      SemanticHitField.username || SemanticHitField.summary => 5,
      SemanticHitField.url || SemanticHitField.secretNote => 4,
      SemanticHitField.tags => 3,
      SemanticHitField.noteBody => 2,
      null => 0,
    };
    if (semantic != 0) {
      return semantic;
    }
    var best = 0;
    for (final field in item.keywordHitFields) {
      final priority = switch (field) {
        SearchSourceField.secretTitle || SearchSourceField.noteTitle => 6,
        SearchSourceField.secretUsername || SearchSourceField.noteSummary => 5,
        SearchSourceField.secretWebsiteUrl || SearchSourceField.secretNote => 4,
        SearchSourceField.secretTags || SearchSourceField.noteTags => 3,
        SearchSourceField.noteBody => 2,
        SearchSourceField.secretPassword => 1,
      };
      if (priority > best) {
        best = priority;
      }
    }
    return best;
  }

  bool _shouldKeepUnifiedResult(SearchResultItem item) {
    final semanticOnly =
        item.matchSources.length == 1 &&
        item.matchSources.contains(SearchMatchSource.semantic);
    if (!semanticOnly || _qualityTier(item) >= 2) {
      return true;
    }
    return (item.semanticScore ?? 0) >= 0.90;
  }

  int _sourcePriority(Set<SearchMatchSource> sources) {
    if (sources.contains(SearchMatchSource.keyword) &&
        sources.contains(SearchMatchSource.semantic)) {
      return 3;
    }
    return sources.contains(SearchMatchSource.semantic) ? 2 : 1;
  }

  String _keyFor(SearchResultItem item) => '${item.type.name}:${item.id}';
}
