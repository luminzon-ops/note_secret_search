import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/composition/shared_preferences_composition.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/core/storage/database/app_database_providers.dart';
import 'package:note_secret_search/core/storage/database/sqlite_protected_configuration_repository.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_sensitive_providers.dart';
import 'package:note_secret_search/features/ai_models/application/model_download_providers.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/shared_preferences_active_model_selection_store.dart';
import 'package:note_secret_search/features/notes/application/note_providers.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/search/application/content_mutation_search_coordinator.dart';
import 'package:note_secret_search/features/search/application/embedding_runtime_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/infrastructure/embedding_runtime_bridge.dart';
import 'package:note_secret_search/features/search/infrastructure/onnx_embedding_engine.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_search_configuration_repository.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';
import 'package:note_secret_search/features/vault/infrastructure/sqlite_vault_repository.dart';

final List<Override> contentSearchCompositionOverrides = <Override>[
  vaultRepositoryProvider.overrideWith((ref) {
    return SqliteVaultRepository(database: ref.watch(appDatabaseProvider));
  }),
  noteRepositoryProvider.overrideWith((ref) {
    return SqliteNoteRepository(database: ref.watch(appDatabaseProvider));
  }),
  secretRepositoryProvider.overrideWith((ref) {
    return SqliteSecretRepository(database: ref.watch(appDatabaseProvider));
  }),
  sqliteEmbeddingRepositoryProvider.overrideWith((ref) {
    return SqliteEmbeddingRepository(database: ref.watch(appDatabaseProvider));
  }),
  searchConfigurationRepositoryProvider.overrideWith((ref) async {
    final preferences = await ref.watch(sharedPreferencesProvider.future);
    final protectedRepository = SqliteProtectedConfigurationRepository(
      database: ref.watch(appDatabaseProvider),
      cryptoService: ref.watch(cryptoServiceProvider),
    );
    return SqliteSearchConfigurationRepository(
      preferences: preferences,
      loadAppSetting: protectedRepository.loadAppSetting,
      saveAppSetting: protectedRepository.saveAppSetting,
    );
  }),
  embeddingRuntimeBridgeProvider.overrideWith((ref) {
    return MethodChannelEmbeddingRuntimeBridge();
  }),
  embeddingEngineProvider.overrideWith((ref) {
    return OnnxEmbeddingEngine(
      bridge: ref.watch(embeddingRuntimeBridgeProvider),
      resolveMetadata: ref.watch(embeddingModelMetadataResolverProvider),
    );
  }),
  activeModelSelectionStoreProvider.overrideWith((ref) async {
    final preferences = await ref.watch(sharedPreferencesProvider.future);
    return SharedPreferencesActiveModelSelectionStore(preferences: preferences);
  }),
  modelSelectionRegistryEntriesProvider.overrideWith((ref) {
    return ref.watch(modelRegistryEntriesProvider.future);
  }),
  modelSelectionEmbeddingRuntimeStatesProvider.overrideWith((ref) {
    return ref.watch(embeddingRuntimeStatesProvider.future);
  }),
  activeEmbeddingSelectionEffectsProvider.overrideWith((ref) {
    return _ComposedActiveEmbeddingSelectionEffects(
      writeFence: ref.watch(searchIndexWriteFenceProvider),
      runtimeBridge: ref.watch(embeddingRuntimeBridgeProvider),
    );
  }),
  contentMutationSearchSynchronizerProvider.overrideWith((ref) {
    return ContentMutationSearchCoordinator(
      loadActiveEmbeddingModel: () {
        return ref.read(activeEmbeddingModelProvider.future);
      },
      loadIndexSettings: () {
        return ref.read(searchIndexSettingsProvider.future);
      },
      indexPending: () {
        return ref
            .read(indexPendingSearchUseCaseProvider)
            .execute(
              taskState: ref.read(searchIndexTaskStateProvider),
              onTaskState: (_) {},
            )
            .then((_) {});
      },
      invalidateSearchProjections: () {
        ref.invalidate(searchIndexStatusSnapshotProvider);
        ref.invalidate(semanticSearchResultsProvider);
        ref.invalidate(unifiedSearchResultsProvider);
      },
    );
  }),
];

class _ComposedActiveEmbeddingSelectionEffects
    implements ActiveEmbeddingSelectionEffects {
  const _ComposedActiveEmbeddingSelectionEffects({
    required SearchIndexWriteFence writeFence,
    required EmbeddingRuntimeBridge runtimeBridge,
  }) : _writeFence = writeFence,
       _runtimeBridge = runtimeBridge;

  final SearchIndexWriteFence _writeFence;
  final EmbeddingRuntimeBridge _runtimeBridge;

  @override
  Future<void> prepareForPersistence({
    required String? previousModelId,
    required String? nextModelId,
  }) async {
    _writeFence.invalidate();
    if (previousModelId == null ||
        previousModelId.isEmpty ||
        previousModelId == nextModelId) {
      return;
    }
    await _runtimeBridge.releaseModel(modelId: previousModelId);
  }
}
