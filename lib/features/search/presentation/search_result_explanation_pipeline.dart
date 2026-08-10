part of 'search_result_explanation.dart';

SearchPipelineTopSummary buildSearchPipelineTopSummary({
  required List<SearchResultItem> unifiedResults,
  required List<SemanticSearchResult> semanticResults,
  SearchFusionDiagnostics? fusionDiagnostics,
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
      fusionDiagnostics: fusionDiagnostics,
    ),
    showSemanticQualityHint: hasSemanticInUnified && semanticResultCount > 0,
  );
}
