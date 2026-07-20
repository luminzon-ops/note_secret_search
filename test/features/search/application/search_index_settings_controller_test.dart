import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/search/application/search_index_settings_providers.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_configuration_repository.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';

void main() {
  test(
    'saving index settings preserves the current unified search scope',
    () async {
      final current = SearchConfiguration.defaults().copyWith(
        includeSecretNote: false,
        includeNoteBody: false,
      );
      final repository = _RecordingSearchConfigurationRepository(current);
      final container = ProviderContainer(
        overrides: <Override>[
          searchConfigurationProvider.overrideWith((ref) async => current),
          searchConfigurationRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(searchIndexSettingsControllerProvider)
          .update(
            const SearchIndexSettings(
              autoIndexEnabled: false,
              maxChunkLength: 160,
            ),
          );

      expect(repository.lastDesired?.includeSecretNote, isFalse);
      expect(repository.lastDesired?.includeNoteBody, isFalse);
      expect(repository.lastDesired?.autoIndexEnabled, isFalse);
      expect(repository.lastDesired?.maxChunkLength, 160);
    },
  );
}

class _RecordingSearchConfigurationRepository
    implements SearchConfigurationRepository {
  _RecordingSearchConfigurationRepository(this.current);

  final SearchConfiguration current;
  SearchConfiguration? lastDesired;

  @override
  Future<SearchConfiguration> load() async => current;

  @override
  Future<SearchConfiguration> save(SearchConfiguration desired) async {
    lastDesired = desired;
    return current.forSavedUpdate(desired);
  }
}
