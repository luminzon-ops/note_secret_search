import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/composition/shared_preferences_composition.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/database_session_keys.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_protected_configuration_repository.dart';
import 'package:note_secret_search/features/ai_chat/application/ai_chat_providers.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/sqlite_model_registry_repository.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_model_revision_provider.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_search_configuration_repository.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/vault/infrastructure/sqlite_vault_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/sqlite_test_database.dart';

part 'search_index_pipeline_integration_cases.dart';
part 'search_index_pipeline_integration_fixture.dart';

const _modelRevision =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _staleModelRevision =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _sharedSourceId = 'shared-source';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _runSearchIndexPipelineIntegrationCases();
}
