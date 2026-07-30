import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/ai_providers/application/ai_provider_providers.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_client.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_consent_store.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'ai_provider_providers_consent_cases.dart';
part 'ai_provider_providers_fakes.dart';
part 'ai_provider_providers_settings_cases.dart';
part 'ai_provider_providers_status_cases.dart';

void main() {
  _runAiProviderStatusCases();
  _runAiProviderConsentCases();
  _runAiProviderSettingsCases();
}
