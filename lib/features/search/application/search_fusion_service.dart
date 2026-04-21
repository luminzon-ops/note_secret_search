import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

class SearchFusionService {
  const SearchFusionService();

  List<SearchResultItem> fuse({
    required List<SearchResultItem> keywordResults,
    required List<SemanticSearchResult> semanticResults,
  }) {
    final byKey = <String, SearchResultItem>{};

    for (final item in keywordResults) {
      byKey[_keyFor(item)] = item.copyWith(
        matchSources: <SearchMatchSource>{...item.matchSources, SearchMatchSource.keyword},
      );
    }

    for (final semantic in semanticResults) {
      final key = _keyFor(semantic.item);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = semantic.item.copyWith(
          matchSources: <SearchMatchSource>{SearchMatchSource.semantic},
          semanticScore: semantic.score,
        );
        continue;
      }

      byKey[key] = existing.copyWith(
        matchSources: <SearchMatchSource>{...existing.matchSources, SearchMatchSource.semantic},
        semanticScore: _maxScore(existing.semanticScore, semantic.score),
        semanticHitSummary: semantic.hitSummary,
        semanticHitField: semantic.hitField,
      );
    }

    final results = byKey.values.toList(growable: false);
    results.sort((a, b) {
      final sourcePriority = _sourcePriority(b.matchSources).compareTo(_sourcePriority(a.matchSources));
      if (sourcePriority != 0) {
        return sourcePriority;
      }

      final semanticSort = (b.semanticScore ?? -1).compareTo(a.semanticScore ?? -1);
      if (semanticSort != 0) {
        return semanticSort;
      }

      final fieldPrioritySort =
          _semanticFieldPriority(b.semanticHitField).compareTo(_semanticFieldPriority(a.semanticHitField));
      if (fieldPrioritySort != 0) {
        return fieldPrioritySort;
      }

      final favoriteSort = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
      if (favoriteSort != 0) {
        return favoriteSort;
      }

      return b.updatedAt.compareTo(a.updatedAt);
    });

    return results;
  }

  String _keyFor(SearchResultItem item) => '${item.type.name}:${item.id}';

  int _sourcePriority(Set<SearchMatchSource> sources) {
    if (sources.contains(SearchMatchSource.keyword) && sources.contains(SearchMatchSource.semantic)) {
      return 2;
    }
    if (sources.contains(SearchMatchSource.semantic)) {
      return 1;
    }
    return 0;
  }

  double _maxScore(double? existing, double incoming) {
    if (existing == null) {
      return incoming;
    }
    return existing >= incoming ? existing : incoming;
  }

  int _semanticFieldPriority(SemanticHitField? field) {
    switch (field) {
      case SemanticHitField.title:
        return 6;
      case SemanticHitField.username:
      case SemanticHitField.summary:
        return 5;
      case SemanticHitField.url:
      case SemanticHitField.secretNote:
        return 4;
      case SemanticHitField.tags:
        return 3;
      case SemanticHitField.noteBody:
        return 2;
      case null:
        return 0;
    }
  }
}
