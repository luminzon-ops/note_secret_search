part of 'search_result_explanation.dart';

class SemanticTierCounts {
  const SemanticTierCounts({
    required this.highQualityCount,
    required this.assistCount,
  });

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

  return SemanticTierCounts(
    highQualityCount: highQualityCount,
    assistCount: assistCount,
  );
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
    SearchResultHitLabel.keywordPrimary
        when semanticAssistCount > 0 || dualCount > 0 =>
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
