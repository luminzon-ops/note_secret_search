import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/application/semantic_quality_policy.dart';

enum SearchFusionRejectionReason { weakSemanticAssist, finalResultLimit }

class SearchFusionRejection {
  const SearchFusionRejection({
    required this.identity,
    required this.reason,
    required this.semanticOnly,
  });

  final SearchResultIdentity identity;
  final SearchFusionRejectionReason reason;
  final bool semanticOnly;
}

class SearchFusionDiagnostics {
  const SearchFusionDiagnostics({
    required this.semanticCandidateCount,
    required this.dualHitCount,
    required this.semanticOnlyCandidateCount,
    required this.admittedSemanticOnlyCount,
    required this.keptSemanticOnlyCount,
    required this.rejections,
  });

  final int semanticCandidateCount;
  final int dualHitCount;
  final int semanticOnlyCandidateCount;
  final int admittedSemanticOnlyCount;
  final int keptSemanticOnlyCount;
  final List<SearchFusionRejection> rejections;

  int rejectionCount(SearchFusionRejectionReason reason) {
    return rejections.where((item) => item.reason == reason).length;
  }
}

class SearchFusionOutcome {
  const SearchFusionOutcome({
    required this.results,
    required this.admittedSemanticResults,
    required this.diagnostics,
  });

  final List<SearchResultItem> results;
  final List<SemanticSearchResult> admittedSemanticResults;
  final SearchFusionDiagnostics diagnostics;
}

class SearchFusionService {
  const SearchFusionService({
    SemanticQualityPolicy qualityPolicy =
        const SemanticQualityPolicy.conservativeMvp(),
  }) : _qualityPolicy = qualityPolicy;

  final SemanticQualityPolicy _qualityPolicy;

  List<SearchResultItem> fuse({
    required List<SearchResultItem> keywordResults,
    required List<SemanticSearchResult> semanticResults,
    String query = '',
  }) {
    return fuseDetailed(
      keywordResults: keywordResults,
      semanticResults: semanticResults,
      query: query,
    ).results;
  }

  SearchFusionOutcome fuseDetailed({
    required List<SearchResultItem> keywordResults,
    required List<SemanticSearchResult> semanticResults,
    String query = '',
  }) {
    final byKey = <SearchResultIdentity, SearchResultItem>{};
    final keywordKeys = <SearchResultIdentity>{};
    final semanticByKey = <SearchResultIdentity, SemanticSearchResult>{};
    for (final item in keywordResults) {
      final keywordEvidence = _keywordEvidence(item);
      final key = _keyFor(item);
      keywordKeys.add(key);
      byKey[key] = item.copyWith(
        matchSources: <SearchMatchSource>{
          ...item.matchSources,
          SearchMatchSource.keyword,
        },
        evidence: keywordEvidence,
      );
    }
    for (final semantic in semanticResults) {
      final key = _keyFor(semantic.item);
      final previousSemantic = semanticByKey[key];
      if (previousSemantic == null || semantic.score > previousSemantic.score) {
        semanticByKey[key] = semantic;
      }
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
      final evidence = incomingWins
          ? _mergeEvidence(_keywordEvidence(base), semantic.evidence)
          : base.evidence;
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
        evidence: evidence,
      );
    }

    final admitted = <SearchResultItem>[];
    final weakRejectedKeys = <SearchResultIdentity>{};
    for (final item in byKey.values) {
      if (_shouldKeepUnifiedResult(item)) {
        admitted.add(item);
      } else {
        weakRejectedKeys.add(item.identity);
      }
    }
    admitted.sort((left, right) => _compare(query, left, right));
    final results = List<SearchResultItem>.unmodifiable(admitted.take(100));
    final resultKeys = results.map((item) => item.identity).toSet();
    final semanticOnlyKeys = semanticByKey.keys
        .where((key) => !keywordKeys.contains(key))
        .toSet();
    final rejections = <SearchFusionRejection>[
      for (final key in weakRejectedKeys)
        SearchFusionRejection(
          identity: key,
          reason: SearchFusionRejectionReason.weakSemanticAssist,
          semanticOnly: true,
        ),
      for (final key in semanticByKey.keys)
        if (!weakRejectedKeys.contains(key) && !resultKeys.contains(key))
          SearchFusionRejection(
            identity: key,
            reason: SearchFusionRejectionReason.finalResultLimit,
            semanticOnly: semanticOnlyKeys.contains(key),
          ),
    ];
    final admittedSemanticResults = <SemanticSearchResult>[
      for (final item in results)
        if (semanticByKey[item.identity] case final semantic?) semantic,
    ];
    final admittedSemanticOnlyCount = semanticOnlyKeys
        .where((key) => !weakRejectedKeys.contains(key))
        .length;

    return SearchFusionOutcome(
      results: results,
      admittedSemanticResults: List<SemanticSearchResult>.unmodifiable(
        admittedSemanticResults,
      ),
      diagnostics: SearchFusionDiagnostics(
        semanticCandidateCount: semanticByKey.length,
        dualHitCount: semanticByKey.keys.where(keywordKeys.contains).length,
        semanticOnlyCandidateCount: semanticOnlyKeys.length,
        admittedSemanticOnlyCount: admittedSemanticOnlyCount,
        keptSemanticOnlyCount: semanticOnlyKeys
            .where(resultKeys.contains)
            .length,
        rejections: List<SearchFusionRejection>.unmodifiable(rejections),
      ),
    );
  }

  SearchFusionDiagnostics diagnoseFinalResults({
    required List<SearchResultItem> unifiedResults,
    required List<SemanticSearchResult> semanticResults,
  }) {
    final unifiedByKey = <SearchResultIdentity, SearchResultItem>{
      for (final item in unifiedResults) item.identity: item,
    };
    final semanticByKey = <SearchResultIdentity, SemanticSearchResult>{};
    for (final result in semanticResults) {
      final key = result.item.identity;
      final previous = semanticByKey[key];
      if (previous == null || result.score > previous.score) {
        semanticByKey[key] = result;
      }
    }

    final semanticOnlyKeys = <SearchResultIdentity>{};
    final rejections = <SearchFusionRejection>[];
    for (final entry in semanticByKey.entries) {
      final unified = unifiedByKey[entry.key];
      if (unified?.matchSources.contains(SearchMatchSource.keyword) == true) {
        continue;
      }
      semanticOnlyKeys.add(entry.key);
      if (unified != null) {
        continue;
      }
      final result = entry.value;
      final admitted = _qualityPolicy.admitsSemanticOnly(
        fieldQualityTier: result.fieldQualityTier,
        aggregateRankingScore: result.score,
      );
      rejections.add(
        SearchFusionRejection(
          identity: entry.key,
          reason: admitted
              ? SearchFusionRejectionReason.finalResultLimit
              : SearchFusionRejectionReason.weakSemanticAssist,
          semanticOnly: true,
        ),
      );
    }

    return SearchFusionDiagnostics(
      semanticCandidateCount: semanticByKey.length,
      dualHitCount: semanticByKey.keys
          .where(
            (key) =>
                unifiedByKey[key]?.matchSources.contains(
                  SearchMatchSource.keyword,
                ) ==
                true,
          )
          .length,
      semanticOnlyCandidateCount: semanticOnlyKeys.length,
      admittedSemanticOnlyCount: semanticOnlyKeys
          .where(
            (key) => !rejections.any(
              (rejection) =>
                  rejection.identity == key &&
                  rejection.reason ==
                      SearchFusionRejectionReason.weakSemanticAssist,
            ),
          )
          .length,
      keptSemanticOnlyCount: semanticOnlyKeys
          .where(unifiedByKey.containsKey)
          .length,
      rejections: List<SearchFusionRejection>.unmodifiable(rejections),
    );
  }

  List<SemanticSearchResult> admittedSemanticResultsForFinalResults({
    required List<SearchResultItem> unifiedResults,
    required List<SemanticSearchResult> semanticResults,
  }) {
    final semanticByKey = <SearchResultIdentity, SemanticSearchResult>{};
    for (final result in semanticResults) {
      final key = result.item.identity;
      final previous = semanticByKey[key];
      if (previous == null || result.score > previous.score) {
        semanticByKey[key] = result;
      }
    }
    return List<SemanticSearchResult>.unmodifiable([
      for (final item in unifiedResults)
        if (item.matchSources.contains(SearchMatchSource.semantic))
          if (semanticByKey[item.identity] case final result?) result,
    ]);
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
    var affinity = item.semanticQueryAffinity;
    final normalized = query.trim();
    if (normalized.contains('@') &&
        _fields(item).contains(SearchSourceField.secretUsername)) {
      affinity = 1;
    }
    if ((normalized.contains('://') ||
            normalized.contains('.') ||
            normalized.contains('/')) &&
        _fields(item).contains(SearchSourceField.secretWebsiteUrl)) {
      affinity = 1;
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{1,24}$').hasMatch(normalized) &&
        _fields(item).any(
          (field) =>
              field == SearchSourceField.secretTags ||
              field == SearchSourceField.noteTags,
        )) {
      affinity = 1;
    }
    return affinity;
  }

  int _qualityTier(SearchResultItem item) {
    var best = item.semanticFieldQualityTier;
    for (final field in _fields(item)) {
      final tier = _isHighValueKeywordField(field) ? 2 : 1;
      if (tier > best) {
        best = tier;
      }
    }
    return best == 0 ? 1 : best;
  }

  bool _isHighValueKeywordField(SearchSourceField field) {
    return field == SearchSourceField.secretTitle ||
        field == SearchSourceField.noteTitle ||
        field == SearchSourceField.secretUsername ||
        field == SearchSourceField.noteSummary;
  }

  int _fieldPriority(SearchResultItem item) {
    var best = 0;
    for (final field in _fields(item)) {
      final priority = _sourceFieldPriority(field);
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
    return _qualityPolicy.admitsSemanticOnly(
      fieldQualityTier: _qualityTier(item),
      aggregateRankingScore: item.semanticScore ?? 0,
    );
  }

  int _sourcePriority(Set<SearchMatchSource> sources) {
    if (sources.contains(SearchMatchSource.keyword) &&
        sources.contains(SearchMatchSource.semantic)) {
      return 3;
    }
    return sources.contains(SearchMatchSource.semantic) ? 2 : 1;
  }

  List<SearchEvidence> _keywordEvidence(SearchResultItem item) {
    final evidence = <SearchEvidence>[...item.evidence];
    final existing = evidence
        .where((item) => item.kind == SearchEvidenceKind.keyword)
        .map((item) => item.sourceField)
        .toSet();
    for (final field in item.keywordHitFields) {
      if (existing.add(field)) {
        evidence.add(SearchEvidence.keyword(sourceField: field));
      }
    }
    return List<SearchEvidence>.unmodifiable(evidence);
  }

  List<SearchEvidence> _mergeEvidence(
    List<SearchEvidence> left,
    List<SearchEvidence> right,
  ) {
    final merged = <SearchEvidence>[];
    final coordinates = <String>{};
    for (final evidence in <SearchEvidence>[...left, ...right]) {
      final coordinate =
          '${evidence.kind.name}:${evidence.sourceField.wireName}:'
          '${evidence.fieldChunkIndex ?? -1}';
      if (coordinates.add(coordinate)) {
        merged.add(evidence);
      }
    }
    return List<SearchEvidence>.unmodifiable(merged);
  }

  Set<SearchSourceField> _fields(SearchResultItem item) {
    final fields = <SearchSourceField>{
      ...item.keywordHitFields,
      ...item.evidence.map((evidence) => evidence.sourceField),
    };
    final legacy = _sourceFieldFor(item.type, item.semanticHitField);
    if (legacy != null) {
      fields.add(legacy);
    }
    return fields;
  }

  SearchSourceField? _sourceFieldFor(
    SearchResultType type,
    SemanticHitField? field,
  ) {
    return switch ((type, field)) {
      (SearchResultType.secret, SemanticHitField.title) =>
        SearchSourceField.secretTitle,
      (SearchResultType.note, SemanticHitField.title) =>
        SearchSourceField.noteTitle,
      (_, SemanticHitField.username) => SearchSourceField.secretUsername,
      (_, SemanticHitField.url) => SearchSourceField.secretWebsiteUrl,
      (_, SemanticHitField.secretNote) => SearchSourceField.secretNote,
      (_, SemanticHitField.summary) => SearchSourceField.noteSummary,
      (_, SemanticHitField.noteBody) => SearchSourceField.noteBody,
      (SearchResultType.secret, SemanticHitField.tags) =>
        SearchSourceField.secretTags,
      (SearchResultType.note, SemanticHitField.tags) =>
        SearchSourceField.noteTags,
      (_, null) => null,
    };
  }

  int _sourceFieldPriority(SearchSourceField field) {
    return switch (field) {
      SearchSourceField.secretTitle || SearchSourceField.noteTitle => 6,
      SearchSourceField.secretUsername || SearchSourceField.noteSummary => 5,
      SearchSourceField.secretWebsiteUrl || SearchSourceField.secretNote => 4,
      SearchSourceField.secretTags || SearchSourceField.noteTags => 3,
      SearchSourceField.noteBody => 2,
      SearchSourceField.secretPassword => 1,
    };
  }

  SearchResultIdentity _keyFor(SearchResultItem item) => item.identity;
}
