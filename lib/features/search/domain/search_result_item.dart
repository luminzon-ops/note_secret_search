enum SearchResultType {
  secret,
  note,
}

enum SearchMatchSource {
  keyword,
  semantic,
}

enum SemanticHitField {
  title,
  username,
  url,
  secretNote,
  summary,
  noteBody,
  tags,
}

class SearchResultItem {
  const SearchResultItem({
    required this.id,
    required this.type,
    required this.title,
    required this.preview,
    required this.tags,
    required this.favorite,
    required this.updatedAt,
    this.matchSources = const <SearchMatchSource>{SearchMatchSource.keyword},
    this.semanticScore,
    this.semanticHitSummary,
    this.semanticHitField,
  });

  final String id;
  final SearchResultType type;
  final String title;
  final String preview;
  final List<String> tags;
  final bool favorite;
  final DateTime updatedAt;
  final Set<SearchMatchSource> matchSources;
  final double? semanticScore;
  final String? semanticHitSummary;
  final SemanticHitField? semanticHitField;

  SearchResultItem copyWith({
    String? id,
    SearchResultType? type,
    String? title,
    String? preview,
    List<String>? tags,
    bool? favorite,
    DateTime? updatedAt,
    Set<SearchMatchSource>? matchSources,
    double? semanticScore,
    bool clearSemanticScore = false,
    String? semanticHitSummary,
    bool clearSemanticHitSummary = false,
    SemanticHitField? semanticHitField,
    bool clearSemanticHitField = false,
  }) {
    return SearchResultItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      tags: tags ?? this.tags,
      favorite: favorite ?? this.favorite,
      updatedAt: updatedAt ?? this.updatedAt,
      matchSources: matchSources ?? this.matchSources,
      semanticScore: clearSemanticScore ? null : (semanticScore ?? this.semanticScore),
      semanticHitSummary: clearSemanticHitSummary
          ? null
          : (semanticHitSummary ?? this.semanticHitSummary),
      semanticHitField: clearSemanticHitField ? null : (semanticHitField ?? this.semanticHitField),
    );
  }
}
