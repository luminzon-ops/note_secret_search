import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_configuration_repository.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';

final searchConfigurationRepositoryProvider =
    FutureProvider<SearchConfigurationRepository>((ref) {
      throw StateError(
        'searchConfigurationRepositoryProvider must be overridden by '
        'app composition',
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
    maxChunkLength: configuration.maxChunkLength,
  );
});

final searchScopeConfigProvider = FutureProvider<SearchScopeConfig>((
  ref,
) async {
  final configuration = await ref.watch(searchConfigurationProvider.future);
  return SearchScopeConfig(
    includeTitle: configuration.includeTitle,
    includeSecretNote: configuration.includeSecretNote,
    includePasswordField: configuration.includePasswordField,
    includeUsername: configuration.includeUsername,
    includeUrl: configuration.includeUrl,
    includeTags: configuration.includeTags,
    includeNoteBody: configuration.includeNoteBody,
    allowLocalEmbedding: configuration.allowLocalEmbedding,
    allowExternalProviderAccess: configuration.allowExternalProviderAccess,
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
    _ref.read(searchIndexWriteFenceProvider).invalidate();
    final current = await _ref.read(searchConfigurationProvider.future);
    final repository = await _ref.read(
      searchConfigurationRepositoryProvider.future,
    );
    await repository.save(
      current.copyWith(
        autoIndexEnabled: settings.autoIndexEnabled,
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
}
