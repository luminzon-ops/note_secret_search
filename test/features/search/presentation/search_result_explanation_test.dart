import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/presentation/search_result_explanation.dart';

part 'search_result_explanation_fixtures.dart';
part 'search_result_explanation_card_cases.dart';
part 'search_result_explanation_observability_cases.dart';
part 'search_result_explanation_pipeline_cases.dart';

void main() {
  _runSearchResultCardExplanationCases();
  _runSearchResultObservabilityCases();
  _runSearchResultPipelineCases();
}
