import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/application/search_settings_use_case.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/search/presentation/search_page.dart';
import 'package:note_secret_search/features/notes/presentation/note_detail_page.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/presentation/secret_detail_page.dart';

import '../../../support/widget_test_helpers.dart';

part 'search_page_entry_empty_cases.dart';
part 'search_page_explanation_primary_cases.dart';
part 'search_page_explanation_quality_cases.dart';
part 'search_page_observability_primary_cases.dart';
part 'search_page_observability_details_cases.dart';
part 'search_page_result_cases.dart';
part 'search_page_navigation_cases.dart';
part 'search_page_status_cases.dart';
part 'search_page_refresh_cases.dart';
part 'search_page_handoff_feedback_cases.dart';
part 'search_page_harness.dart';
part 'search_page_fixture.dart';

void main() {
  _registerSearchPageEntryCases();
  _registerSearchPageExplanationPrimaryCases();
  _registerSearchPageSemanticTierCases();
  _registerSearchPageObservabilityPrimaryCases();
  _registerSearchPageObservabilityDetailCases();
  _registerSearchPageQualityHintCase();
  _registerSearchPageEmptyCases();
  _registerSearchPageResultStructureCase();
  _registerSearchPageResultExplanationCase();
  _registerSearchPageStatusCases();
  _registerSearchPageRefreshSessionCases();
  _registerSearchPageHandoffCases();
  _registerSearchPageResultSummaryCases();
  _registerSearchPageFeedbackMismatchCase();
  _registerSearchPageNavigationCases();
  _registerSearchPageRefreshRecommendationCases();
}
