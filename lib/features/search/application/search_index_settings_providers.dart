import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/features/search/application/search_providers.dart';
import 'package:note_secret_search/features/search/domain/search_index_settings.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

const _autoIndexEnabledKey = 'search.index.auto_index_enabled';
const _includeSecretNotesKey = 'search.index.include_secret_notes';
const _includeNoteBodyKey = 'search.index.include_note_body';
const _maxChunkLengthKey = 'search.index.max_chunk_length';

final searchIndexSettingsProvider = FutureProvider<SearchIndexSettings>((ref) async {
  final preferences = await ref.watch(sharedPreferencesProvider.future);
  return SearchIndexSettings(
    autoIndexEnabled: preferences.getBool(_autoIndexEnabledKey) ?? true,
    includeSecretNotes: preferences.getBool(_includeSecretNotesKey) ?? true,
    includeNoteBody: preferences.getBool(_includeNoteBodyKey) ?? true,
    maxChunkLength: preferences.getInt(_maxChunkLengthKey) ?? 280,
  );
});

final searchIndexSettingsControllerProvider = Provider<SearchIndexSettingsController>((ref) {
  return SearchIndexSettingsController(ref: ref);
});

class SearchIndexSettingsController {
  SearchIndexSettingsController({required Ref ref}) : _ref = ref;

  final Ref _ref;

  Future<void> update(SearchIndexSettings settings) async {
    final preferences = await _ref.read(sharedPreferencesProvider.future);
    await preferences.setBool(_autoIndexEnabledKey, settings.autoIndexEnabled);
    await preferences.setBool(_includeSecretNotesKey, settings.includeSecretNotes);
    await preferences.setBool(_includeNoteBodyKey, settings.includeNoteBody);
    await preferences.setInt(_maxChunkLengthKey, settings.maxChunkLength);
    _ref.invalidate(searchIndexSettingsProvider);
    _ref.invalidate(searchIndexStatusProvider);
  }
}
