import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/core/storage/database/sqlite_protected_configuration_repository.dart';
import 'package:note_secret_search/features/ai_models/application/model_selection_providers.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_configuration_repository.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_search_configuration_repository.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

final searchConfigurationRepositoryProvider =
    FutureProvider<SearchConfigurationRepository>((ref) async {
      final preferences = await ref.watch(sharedPreferencesProvider.future);
      final protected = SqliteProtectedConfigurationRepository(
        database: ref.watch(appDatabaseProvider),
        cryptoService: ref.watch(cryptoServiceProvider),
      );
      return SqliteSearchConfigurationRepository(
        preferences: preferences,
        loadAppSetting: protected.loadAppSetting,
        saveAppSetting: protected.saveAppSetting,
      );
    });

final searchConfigurationProvider = FutureProvider<SearchConfiguration>((
  ref,
) async {
  final repository = await ref.watch(
    searchConfigurationRepositoryProvider.future,
  );
  return repository.load();
});

final effectiveSearchPolicyProvider = FutureProvider<EffectiveSearchPolicy>((
  ref,
) async {
  return EffectiveSearchPolicy(
    await ref.watch(searchConfigurationProvider.future),
  );
});

final searchIndexSettingsProvider = FutureProvider<SearchIndexSettings>((
  ref,
) async {
  final configuration = await ref.watch(searchConfigurationProvider.future);
  return SearchIndexSettings(
    autoIndexEnabled: configuration.autoIndexEnabled,
    includeSecretNotes: configuration.includeSecretNote,
    includeNoteBody: configuration.includeNoteBody,
    maxChunkLength: configuration.maxChunkLength,
  );
});

final searchIndexSettingsControllerProvider =
    Provider<SearchIndexSettingsController>((ref) {
      return SearchIndexSettingsController(ref: ref);
    });

class SearchIndexSettingsController {
  SearchIndexSettingsController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> update(SearchIndexSettings settings) async {
    final current = await _ref.read(searchConfigurationProvider.future);
    final repository = await _ref.read(
      searchConfigurationRepositoryProvider.future,
    );
    await repository.save(
      current.copyWith(
        autoIndexEnabled: settings.autoIndexEnabled,
        includeSecretNote: settings.includeSecretNotes,
        includeNoteBody: settings.includeNoteBody,
        maxChunkLength: settings.maxChunkLength,
      ),
    );
    _invalidateSearchConfiguration(_ref);
  }
}

void invalidateSearchConfiguration(Ref ref) {
  _invalidateSearchConfiguration(ref);
}

void _invalidateSearchConfiguration(Ref ref) {
  ref.invalidate(searchConfigurationProvider);
  ref.invalidate(effectiveSearchPolicyProvider);
  ref.invalidate(searchIndexSettingsProvider);
  ref.invalidate(searchScopeConfigProvider);
  ref.invalidate(keywordSearchResultsProvider);
  ref.invalidate(semanticSearchResultsProvider);
  ref.invalidate(unifiedSearchResultsProvider);
  ref.invalidate(semanticSearchReadinessProvider);
  ref.invalidate(searchIndexStatusProvider);
}
