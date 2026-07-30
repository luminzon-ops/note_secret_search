import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/logging/app_logger.dart';
import 'package:note_secret_search/features/ai_chat/application/llm_runtime_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_models/application/local_llm_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_catalog_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_use_cases.dart';
import 'package:note_secret_search/features/ai_models/domain/active_model_selection.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_repository.dart';
import 'package:note_secret_search/features/ai_models/domain/model_download_task.dart';
import 'package:note_secret_search/features/ai_models/domain/model_lifecycle_store.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/model_download_service.dart';
import 'package:note_secret_search/features/ai_models/presentation/model_management_page.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/widget_test_helpers.dart';

part 'model_management_page_fakes.dart';
part 'model_management_page_fixture.dart';
part 'model_management_page_harness.dart';
part 'model_management_page_summary_cases.dart';
part 'model_management_page_runtime_summary_cases.dart';
part 'model_management_page_catalog_cases.dart';
part 'model_management_page_download_cases.dart';
part 'model_management_page_action_cases.dart';
part 'model_management_page_download_source_cases.dart';
part 'model_management_page_integrity_cases.dart';
part 'model_management_page_trust_copy_cases.dart';
part 'model_management_page_trust_status_copy_cases.dart';
part 'model_management_page_trust_suppression_cases.dart';
part 'model_management_page_activation_cases.dart';

void main() {
  _registerSummaryIntroCases();
  _registerCatalogBasicsCases();
  _registerInstalledSummaryCases();
  _registerRuntimeSummaryCases();
  _registerCatalogDeploymentCases();
  _registerDownloadCases();
  _registerActionCases();
  _registerDownloadSourceCases();
  _registerIntegrityCases();
  _registerTrustCopyCases();
  _registerTrustStatusCopyCases();
  _registerTrustSuppressionCases();
  _registerActivationCases();
}
