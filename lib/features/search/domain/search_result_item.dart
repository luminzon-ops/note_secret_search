import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_evidence.dart';

enum SearchResultType { secret, note }

enum SearchMatchSource { keyword, semantic }

class SearchResultIdentity {
  const SearchResultIdentity({required this.type, required this.id});

  final SearchResultType type;
  final String id;

  @override
  bool operator ==(Object other) {
    return other is SearchResultIdentity &&
        other.type == type &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(type, id);
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
    this.semanticRawSimilarity,
    this.semanticHitSummary,
    this.semanticHitField,
    this.semanticQueryAffinity = 0,
    this.semanticFieldQualityTier = 0,
    this.keywordHitFields = const <SearchSourceField>[],
    this.evidence = const <SearchEvidence>[],
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
  final double? semanticRawSimilarity;
  final String? semanticHitSummary;
  final SemanticHitField? semanticHitField;
  final int semanticQueryAffinity;
  final int semanticFieldQualityTier;
  final List<SearchSourceField> keywordHitFields;
  final List<SearchEvidence> evidence;

  SearchResultIdentity get identity {
    return SearchResultIdentity(type: type, id: id);
  }

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
    double? semanticRawSimilarity,
    bool clearSemanticRawSimilarity = false,
    String? semanticHitSummary,
    bool clearSemanticHitSummary = false,
    SemanticHitField? semanticHitField,
    bool clearSemanticHitField = false,
    int? semanticQueryAffinity,
    int? semanticFieldQualityTier,
    List<SearchSourceField>? keywordHitFields,
    List<SearchEvidence>? evidence,
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
      semanticScore: clearSemanticScore
          ? null
          : (semanticScore ?? this.semanticScore),
      semanticRawSimilarity: clearSemanticRawSimilarity
          ? null
          : (semanticRawSimilarity ?? this.semanticRawSimilarity),
      semanticHitSummary: clearSemanticHitSummary
          ? null
          : (semanticHitSummary ?? this.semanticHitSummary),
      semanticHitField: clearSemanticHitField
          ? null
          : (semanticHitField ?? this.semanticHitField),
      semanticQueryAffinity:
          semanticQueryAffinity ?? this.semanticQueryAffinity,
      semanticFieldQualityTier:
          semanticFieldQualityTier ?? this.semanticFieldQualityTier,
      keywordHitFields: keywordHitFields ?? this.keywordHitFields,
      evidence: evidence ?? this.evidence,
    );
  }
}
