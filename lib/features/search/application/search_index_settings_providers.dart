import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/application/search_settings_use_case.dart';
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

final searchSettingsUseCaseProvider = Provider<SearchSettingsUseCase>((ref) {
  return SearchSettingsUseCase(
    writeFence: ref.watch(searchIndexWriteFenceProvider),
    loadConfiguration: () {
      return ref.read(searchConfigurationProvider.future);
    },
    loadRepository: () {
      return ref.read(searchConfigurationRepositoryProvider.future);
    },
    invalidateConfiguration: () {
      invalidateSearchConfiguration(ref);
    },
  );
});

void invalidateSearchConfiguration(Ref ref) {
  ref.invalidate(searchConfigurationProvider);
  ref.invalidate(searchIndexSettingsProvider);
  ref.invalidate(searchScopeConfigProvider);
}
