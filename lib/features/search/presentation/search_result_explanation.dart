import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

enum SearchResultHitLabel {
  dual,
  keywordPrimary,
  semanticAssist,
}

enum SemanticExplanationTier {
  none,
  highQuality,
  assist,
}

class SearchResultExplanationSummary {
  const SearchResultExplanationSummary({
    required this.headline,
    required this.breakdown,
    this.semanticTierBreakdown,
  });

  final String headline;
  final String breakdown;
  final String? semanticTierBreakdown;
}

class SearchObservabilitySummary {
  const SearchObservabilitySummary({
    required this.hitBreakdown,
    required this.semanticTierBreakdown,
    required this.dominantSignalHint,
    this.semanticFieldBreakdown,
    this.semanticOnlyFilteringBreakdown,
    this.semanticOnlyFilteringReason,
    this.dominantFieldHint,
    this.reminderHint,
  });

  final String hitBreakdown;
  final String semanticTierBreakdown;
  final String dominantSignalHint;
  final String? semanticFieldBreakdown;
  final String? semanticOnlyFilteringBreakdown;
  final String? semanticOnlyFilteringReason;
  final String? dominantFieldHint;
  final String? reminderHint;
}

class SearchPipelineTopSummary {
  const SearchPipelineTopSummary({
    required this.summaryText,
    required this.keywordCount,
    required this.semanticResultCount,
    required this.explanation,
    required this.observability,
    required this.showSemanticQualityHint,
  });

  final String summaryText;
  final int keywordCount;
  final int semanticResultCount;
  final SearchResultExplanationSummary explanation;
  final SearchObservabilitySummary observability;
  final bool showSemanticQualityHint;
}

class SemanticTierCounts {
  const SemanticTierCounts({required this.highQualityCount, required this.assistCount});

  final int highQualityCount;
  final int assistCount;

  bool get hasSemanticTiering => highQualityCount > 0 || assistCount > 0;
}

SemanticExplanationTier classifySemanticExplanationTier(SearchResultItem item) {
  final hasSemantic = item.matchSources.contains(SearchMatchSource.semantic);
  if (!hasSemantic) {
    return SemanticExplanationTier.none;
  }

  switch (item.semanticHitField) {
    case SemanticHitField.title:
    case SemanticHitField.username:
    case SemanticHitField.summary:
      return SemanticExplanationTier.highQuality;
    case SemanticHitField.url:
    case SemanticHitField.secretNote:
    case SemanticHitField.tags:
    case SemanticHitField.noteBody:
      return SemanticExplanationTier.assist;
    case null:
      return SemanticExplanationTier.none;
  }
}

SemanticTierCounts countSemanticExplanationTiers(List<SearchResultItem> items) {
  var highQualityCount = 0;
  var assistCount = 0;

  for (final item in items) {
    switch (classifySemanticExplanationTier(item)) {
      case SemanticExplanationTier.highQuality:
        highQualityCount++;
        break;
      case SemanticExplanationTier.assist:
        assistCount++;
        break;
      case SemanticExplanationTier.none:
        break;
    }
  }

  return SemanticTierCounts(highQualityCount: highQualityCount, assistCount: assistCount);
}

String? buildSemanticTierBreakdown(List<SearchResultItem> items) {
  final counts = countSemanticExplanationTiers(items);
  if (!counts.hasSemanticTiering) {
    return null;
  }
  return '当前语义结果中，重点语义命中 ${counts.highQualityCount} 条，补充语义线索 ${counts.assistCount} 条。';
}

String? resolveSemanticTierReason(SearchResultItem item) {
  switch (classifySemanticExplanationTier(item)) {
    case SemanticExplanationTier.highQuality:
      switch (item.semanticHitField) {
        case SemanticHitField.title:
          return '重点语义命中：标题属于高可信语义字段';
        case SemanticHitField.username:
          return '重点语义命中：账号属于高可信语义字段';
        case SemanticHitField.summary:
          return '重点语义命中：摘要属于高可信语义字段';
        case SemanticHitField.url:
        case SemanticHitField.secretNote:
        case SemanticHitField.tags:
        case SemanticHitField.noteBody:
        case null:
          return null;
      }
    case SemanticExplanationTier.assist:
      switch (item.semanticHitField) {
        case SemanticHitField.url:
          return '补充语义线索：网址属于补充语义线索';
        case SemanticHitField.secretNote:
          return '补充语义线索：附注属于补充语义线索';
        case SemanticHitField.tags:
          return '补充语义线索：标签属于补充语义线索';
        case SemanticHitField.noteBody:
          return '补充语义线索：正文属于补充语义线索';
        case SemanticHitField.title:
        case SemanticHitField.username:
        case SemanticHitField.summary:
        case null:
          return null;
      }
    case SemanticExplanationTier.none:
      return null;
  }
}

SearchResultHitLabel classifySearchResultHit(SearchResultItem item) {
  final hasKeyword = item.matchSources.contains(SearchMatchSource.keyword);
  final hasSemantic = item.matchSources.contains(SearchMatchSource.semantic);

  if (hasKeyword && hasSemantic) {
    return SearchResultHitLabel.dual;
  }
  if (hasKeyword) {
    return SearchResultHitLabel.keywordPrimary;
  }
  return SearchResultHitLabel.semanticAssist;
}

String resolveSearchResultHitLabel(SearchResultItem item) {
  switch (classifySearchResultHit(item)) {
    case SearchResultHitLabel.dual:
      return '双命中';
    case SearchResultHitLabel.keywordPrimary:
      return '关键词优先';
    case SearchResultHitLabel.semanticAssist:
      return '语义命中';
  }
}

String? buildSearchResultCardExplanation(SearchResultItem item) {
  final hitLabel = classifySearchResultHit(item);
  final semanticTier = classifySemanticExplanationTier(item);

  switch (hitLabel) {
    case SearchResultHitLabel.dual:
      switch (semanticTier) {
        case SemanticExplanationTier.highQuality:
          return '这条结果同时命中关键词与重点语义字段，可优先查看。';
        case SemanticExplanationTier.assist:
          return '这条结果同时命中关键词，语义部分主要提供补充线索，建议结合预览确认。';
        case SemanticExplanationTier.none:
          return '这条结果主要由关键词命中进入结果。';
      }
    case SearchResultHitLabel.keywordPrimary:
      return '这条结果主要由关键词命中进入结果。';
    case SearchResultHitLabel.semanticAssist:
      switch (semanticTier) {
        case SemanticExplanationTier.highQuality:
          return '这条结果主要由重点语义命中支持，适合优先检查。';
        case SemanticExplanationTier.assist:
          return '这条结果主要由补充语义线索召回，建议继续确认。';
        case SemanticExplanationTier.none:
          return null;
      }
  }
}

SearchResultExplanationSummary buildSearchResultExplanationSummary(
  List<SearchResultItem> unifiedResults,
) {
  final leadingResults = unifiedResults.take(5).toList(growable: false);
  var dualCount = 0;
  var keywordPrimaryCount = 0;
  var semanticAssistCount = 0;

  for (final item in leadingResults) {
    switch (classifySearchResultHit(item)) {
      case SearchResultHitLabel.dual:
        dualCount++;
        break;
      case SearchResultHitLabel.keywordPrimary:
        keywordPrimaryCount++;
        break;
      case SearchResultHitLabel.semanticAssist:
        semanticAssistCount++;
        break;
    }
  }

  final counts = <SearchResultHitLabel, int>{
    SearchResultHitLabel.dual: dualCount,
    SearchResultHitLabel.keywordPrimary: keywordPrimaryCount,
    SearchResultHitLabel.semanticAssist: semanticAssistCount,
  };

  const priority = <SearchResultHitLabel>[
    SearchResultHitLabel.dual,
    SearchResultHitLabel.keywordPrimary,
    SearchResultHitLabel.semanticAssist,
  ];

  var dominant = SearchResultHitLabel.keywordPrimary;
  var dominantCount = -1;
  for (final label in priority) {
    final count = counts[label] ?? 0;
    if (count > dominantCount) {
      dominant = label;
      dominantCount = count;
    }
  }

  final headline = switch (dominant) {
    SearchResultHitLabel.dual => '当前前排结果以双命中为主，关键词与语义信号共同参与排序。',
    SearchResultHitLabel.keywordPrimary when semanticAssistCount > 0 || dualCount > 0 =>
      '当前前排结果以关键词命中为主，语义信号主要用于补充排序。',
    SearchResultHitLabel.keywordPrimary => '当前结果主要来自关键词检索，语义链路尚未明显参与前排排序。',
    SearchResultHitLabel.semanticAssist => '当前前排结果更多依赖语义召回，适合继续检查命中摘要与上下文。',
  };

  return SearchResultExplanationSummary(
    headline: headline,
    breakdown:
        '前 ${leadingResults.length} 条中：双命中 $dualCount 条，关键词优先 $keywordPrimaryCount 条，语义命中 $semanticAssistCount 条。',
    semanticTierBreakdown: buildSemanticTierBreakdown(leadingResults),
  );
}

SearchObservabilitySummary buildSearchObservabilitySummary(
  List<SearchResultItem> unifiedResults, {
  List<SemanticSearchResult> semanticResults = const <SemanticSearchResult>[],
}) {
  var dualCount = 0;
  var keywordPrimaryCount = 0;
  var semanticAssistCount = 0;

  final fieldCounts = <SemanticHitField, int>{};

  for (final item in unifiedResults) {
    switch (classifySearchResultHit(item)) {
      case SearchResultHitLabel.dual:
        dualCount++;
        break;
      case SearchResultHitLabel.keywordPrimary:
        keywordPrimaryCount++;
        break;
      case SearchResultHitLabel.semanticAssist:
        semanticAssistCount++;
        break;
    }

    final field = item.semanticHitField;
    if (field != null && item.matchSources.contains(SearchMatchSource.semantic)) {
      fieldCounts.update(field, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  final tierCounts = countSemanticExplanationTiers(unifiedResults);
  final dominantSignal = _resolveDominantSignal(
    dualCount: dualCount,
    keywordPrimaryCount: keywordPrimaryCount,
    semanticAssistCount: semanticAssistCount,
  );
  final dominantField = _resolveDominantField(fieldCounts);
  final reminderHint = _buildReminderHint(
    dominantSignal: dominantSignal,
    dominantField: dominantField,
    dualCount: dualCount,
    keywordPrimaryCount: keywordPrimaryCount,
    semanticAssistCount: semanticAssistCount,
    highQualitySemanticCount: tierCounts.highQualityCount,
    assistSemanticCount: tierCounts.assistCount,
  );

  final semanticFieldBreakdown = fieldCounts.isEmpty
      ? null
      : '字段分布：${fieldCounts.entries.map((entry) => '${_semanticFieldObservabilityLabel(entry.key)} ${entry.value} 条').join('，')}。';
  final semanticOnlyFilteringBreakdown = _buildSemanticOnlyFilteringBreakdown(
    unifiedResults: unifiedResults,
    semanticResults: semanticResults,
  );
  final semanticOnlyFilteringReason = semanticOnlyFilteringBreakdown == null
      ? null
       : '过滤原因：被过滤结果多数只提供补充语义线索，且未达到高分保留条件。';

  return SearchObservabilitySummary(
    hitBreakdown: '命中结构：双命中 $dualCount 条，关键词优先 $keywordPrimaryCount 条，语义命中 $semanticAssistCount 条。',
    semanticTierBreakdown: '语义分层：重点 ${tierCounts.highQualityCount} 条，补充线索 ${tierCounts.assistCount} 条。',
    dominantSignalHint: _buildDominantSignalHint(
      dominantSignal,
      switch (dominantSignal) {
        SearchResultHitLabel.dual => dualCount,
        SearchResultHitLabel.keywordPrimary => keywordPrimaryCount,
        SearchResultHitLabel.semanticAssist => semanticAssistCount,
      },
    ),
    semanticFieldBreakdown: semanticFieldBreakdown,
    semanticOnlyFilteringBreakdown: semanticOnlyFilteringBreakdown,
    semanticOnlyFilteringReason: semanticOnlyFilteringReason,
    dominantFieldHint: dominantField == null ? null : _buildDominantFieldHint(dominantField, fieldCounts[dominantField]!),
    reminderHint: reminderHint,
  );
}

String? _buildSemanticOnlyFilteringBreakdown({
  required List<SearchResultItem> unifiedResults,
  required List<SemanticSearchResult> semanticResults,
}) {
  if (semanticResults.isEmpty) {
    return null;
  }

  final unifiedKeys = unifiedResults.map(_searchResultItemKey).toSet();
  final semanticOnlyCandidateCount = semanticResults
      .where((result) => !unifiedKeys.contains(_searchResultItemKey(result.item)))
      .length;
  final keptSemanticOnlyCount = unifiedResults.where(_isSemanticOnlyUnifiedResult).length;
  final filteredSemanticOnlyCount = semanticOnlyCandidateCount - keptSemanticOnlyCount;

  if (semanticOnlyCandidateCount <= 0 || filteredSemanticOnlyCount <= 0) {
    return null;
  }

  return '语义过滤：语义直达候选 $semanticOnlyCandidateCount 条，保留 $keptSemanticOnlyCount 条，过滤 $filteredSemanticOnlyCount 条。';
}

bool _isSemanticOnlyUnifiedResult(SearchResultItem item) {
  return item.matchSources.length == 1 && item.matchSources.contains(SearchMatchSource.semantic);
}

String _searchResultItemKey(SearchResultItem item) => '${item.type.name}:${item.id}';

String? _buildReminderHint({
  required SearchResultHitLabel dominantSignal,
  required SemanticHitField? dominantField,
  required int dualCount,
  required int keywordPrimaryCount,
  required int semanticAssistCount,
  required int highQualitySemanticCount,
  required int assistSemanticCount,
}) {
  final weakSemanticParticipation = dualCount + semanticAssistCount <= keywordPrimaryCount;
  if (dominantSignal == SearchResultHitLabel.keywordPrimary && weakSemanticParticipation) {
    return '当前结果主要由关键词命中主导，语义链路参与较弱。';
  }

  const assistFields = <SemanticHitField>{
    SemanticHitField.url,
    SemanticHitField.secretNote,
    SemanticHitField.noteBody,
    SemanticHitField.tags,
  };
  if (dominantField != null && assistFields.contains(dominantField)) {
    return '当前语义参与主要来自辅助字段，建议谨慎判断结果质量。';
  }

  const highValueFields = <SemanticHitField>{
    SemanticHitField.title,
    SemanticHitField.username,
    SemanticHitField.summary,
  };
  if (dominantField != null &&
      highValueFields.contains(dominantField) &&
      highQualitySemanticCount + assistSemanticCount > 1 &&
      highQualitySemanticCount > assistSemanticCount) {
    return '当前语义命中集中在高价值字段，可优先检查前排结果。';
  }

  return null;
}

SearchResultHitLabel _resolveDominantSignal({
  required int dualCount,
  required int keywordPrimaryCount,
  required int semanticAssistCount,
}) {
  final counts = <SearchResultHitLabel, int>{
    SearchResultHitLabel.dual: dualCount,
    SearchResultHitLabel.keywordPrimary: keywordPrimaryCount,
    SearchResultHitLabel.semanticAssist: semanticAssistCount,
  };

  const priority = <SearchResultHitLabel>[
    SearchResultHitLabel.dual,
    SearchResultHitLabel.keywordPrimary,
    SearchResultHitLabel.semanticAssist,
  ];

  var dominant = SearchResultHitLabel.dual;
  var dominantCount = -1;
  for (final label in priority) {
    final count = counts[label] ?? 0;
    if (count > dominantCount) {
      dominant = label;
      dominantCount = count;
    }
  }

  return dominant;
}

String _buildDominantSignalHint(SearchResultHitLabel label, int count) {
  switch (label) {
    case SearchResultHitLabel.dual:
      return '当前结果主要由双命中主导（$count 条）。';
    case SearchResultHitLabel.keywordPrimary:
      return '当前结果主要由关键词命中主导（$count 条）。';
    case SearchResultHitLabel.semanticAssist:
      return '当前结果主要由语义召回主导（$count 条）。';
  }
}

SemanticHitField? _resolveDominantField(Map<SemanticHitField, int> fieldCounts) {
  if (fieldCounts.isEmpty) {
    return null;
  }

  const priority = <SemanticHitField>[
    SemanticHitField.title,
    SemanticHitField.username,
    SemanticHitField.summary,
    SemanticHitField.url,
    SemanticHitField.secretNote,
    SemanticHitField.noteBody,
    SemanticHitField.tags,
  ];

  var dominant = priority.first;
  var dominantCount = -1;
  for (final field in priority) {
    final count = fieldCounts[field] ?? 0;
    if (count > dominantCount) {
      dominant = field;
      dominantCount = count;
    }
  }

  return dominantCount > 0 ? dominant : null;
}

String _buildDominantFieldHint(SemanticHitField field, int count) {
  return '当前语义命中主要集中在${_semanticFieldObservabilityLabel(field)}字段（$count 条）。';
}

SearchPipelineTopSummary buildSearchPipelineTopSummary({
  required List<SearchResultItem> unifiedResults,
  required List<SemanticSearchResult> semanticResults,
}) {
  final semanticResultCount = semanticResults.length;
  final hasSemanticInUnified = unifiedResults.any(
    (item) => item.matchSources.contains(SearchMatchSource.semantic),
  );

  final summaryText = hasSemanticInUnified
      ? '当前统一结果已混合关键词与语义信号，排序会优先展示双命中内容。'
      : '当前仅展示关键词检索结果，语义链路未参与此次结果排序。';

  final keywordCount = unifiedResults
      .where((item) => item.matchSources.contains(SearchMatchSource.keyword))
      .length;

  return SearchPipelineTopSummary(
    summaryText: summaryText,
    keywordCount: keywordCount,
    semanticResultCount: semanticResultCount,
    explanation: buildSearchResultExplanationSummary(unifiedResults),
    observability: buildSearchObservabilitySummary(
      unifiedResults,
      semanticResults: semanticResults,
    ),
    showSemanticQualityHint: hasSemanticInUnified && semanticResultCount > 0,
  );
}

String _semanticFieldObservabilityLabel(SemanticHitField field) {
  switch (field) {
    case SemanticHitField.title:
      return '标题';
    case SemanticHitField.username:
      return '账号';
    case SemanticHitField.url:
      return '网址';
    case SemanticHitField.secretNote:
      return '附注';
    case SemanticHitField.summary:
      return '摘要';
    case SemanticHitField.noteBody:
      return '正文';
    case SemanticHitField.tags:
      return '标签';
  }
}
