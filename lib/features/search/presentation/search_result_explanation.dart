import 'package:note_secret_search/features/search/application/search_fusion_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';

part 'search_result_explanation_card.dart';
part 'search_result_explanation_observability.dart';
part 'search_result_explanation_pipeline.dart';

enum SearchResultHitLabel { dual, keywordPrimary, semanticAssist }

enum SemanticExplanationTier { none, highQuality, assist }

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
    this.semanticVersionBreakdown,
    this.semanticOnlyFilteringBreakdown,
    this.semanticOnlyFilteringReason,
    this.dominantFieldHint,
    this.reminderHint,
  });

  final String hitBreakdown;
  final String semanticTierBreakdown;
  final String dominantSignalHint;
  final String? semanticFieldBreakdown;
  final String? semanticVersionBreakdown;
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
