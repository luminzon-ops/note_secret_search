import 'package:note_secret_search/features/search/application/search_index_write_fence.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_configuration_repository.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';

class SearchSettingsSaveResult {
  const SearchSettingsSaveResult({
    required this.savedConfiguration,
    required this.requiresReindex,
  });

  final SearchConfiguration savedConfiguration;
  final bool requiresReindex;
}

class SearchSettingsUseCase {
  const SearchSettingsUseCase({
    required SearchIndexWriteFence writeFence,
    required Future<SearchConfiguration> Function() loadConfiguration,
    required Future<SearchConfigurationRepository> Function() loadRepository,
    required void Function() invalidateConfiguration,
  }) : _writeFence = writeFence,
       _loadConfiguration = loadConfiguration,
       _loadRepository = loadRepository,
       _invalidateConfiguration = invalidateConfiguration;

  final SearchIndexWriteFence _writeFence;
  final Future<SearchConfiguration> Function() _loadConfiguration;
  final Future<SearchConfigurationRepository> Function() _loadRepository;
  final void Function() _invalidateConfiguration;

  Future<SearchSettingsSaveResult> saveIndexSettings(
    SearchIndexSettings settings,
  ) {
    return _save(
      (current) => current.copyWith(
        autoIndexEnabled: settings.autoIndexEnabled,
        maxChunkLength: settings.maxChunkLength,
      ),
    );
  }

  Future<SearchSettingsSaveResult> saveScope(SearchScopeConfig scope) {
    return _save(
      (current) => current.copyWith(
        includeTitle: scope.includeTitle,
        includeSecretNote: scope.includeSecretNote,
        includePasswordField: scope.includePasswordField,
        includeUsername: scope.includeUsername,
        includeUrl: scope.includeUrl,
        includeTags: scope.includeTags,
        includeNoteBody: scope.includeNoteBody,
        allowLocalEmbedding: scope.allowLocalEmbedding,
        allowExternalProviderAccess: scope.allowExternalProviderAccess,
      ),
    );
  }

  Future<SearchSettingsSaveResult> _save(
    SearchConfiguration Function(SearchConfiguration current) buildDesired,
  ) async {
    _writeFence.invalidate();
    final current = await _loadConfiguration();
    final desired = buildDesired(current);
    final saved = current.forSavedUpdate(desired);
    final repository = await _loadRepository();
    await repository.save(saved);
    _invalidateConfiguration();
    return SearchSettingsSaveResult(
      savedConfiguration: saved,
      requiresReindex:
          searchIndexConfigurationHash(current) !=
          searchIndexConfigurationHash(saved),
    );
  }
}
