import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/application/search_settings_use_case.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_index_status.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/presentation/search_settings_page.dart';
import 'package:note_secret_search/shared/navigation/app_destination.dart';

import '../../../support/widget_test_helpers.dart';

part 'search_settings_page_harness.dart';
part 'search_settings_page_status_cases.dart';
part 'search_settings_page_refresh_cases.dart';
part 'search_settings_page_impact_save_cases.dart';
part 'search_settings_page_guidance_cases.dart';
part 'search_settings_page_status_history_cases.dart';
part 'search_settings_page_model_cases.dart';
part 'search_settings_page_refresh_handoff_cases.dart';

void main() {
  _runSearchSettingsStatusCases();
  _runSearchSettingsRefreshCases();
  _runSearchSettingsImpactSaveCases();
  _runSearchSettingsGuidanceCases();
  _runSearchSettingsStatusHistoryCases();
  _runSearchSettingsModelCases();
  _runSearchSettingsRefreshHandoffCases();
}
