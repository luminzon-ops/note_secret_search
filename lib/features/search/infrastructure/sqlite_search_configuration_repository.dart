import 'dart:convert';

import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_configuration_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String searchConfigurationSettingKey = 'search.configuration';

typedef AppSettingLoader = Future<String?> Function(String key);
typedef AppSettingSaver =
    Future<void> Function({required String key, required String value});

class SqliteSearchConfigurationRepository
    implements SearchConfigurationRepository {
  SqliteSearchConfigurationRepository({
    required SharedPreferences preferences,
    required AppSettingLoader loadAppSetting,
    required AppSettingSaver saveAppSetting,
  }) : _preferences = preferences,
       _loadAppSetting = loadAppSetting,
       _saveAppSetting = saveAppSetting;

  final SharedPreferences _preferences;
  final AppSettingLoader _loadAppSetting;
  final AppSettingSaver _saveAppSetting;

  static const List<String> _legacyKeys = <String>[
    'search.scope.include_title',
    'search.scope.include_secret_note',
    'search.scope.include_password_field',
    'search.scope.include_username',
    'search.scope.include_url',
    'search.scope.include_tags',
    'search.scope.include_note_body',
    'search.scope.allow_local_embedding',
    'search.scope.allow_external_provider_access',
    'search.index.auto_index_enabled',
    'search.index.include_secret_notes',
    'search.index.include_note_body',
    'search.index.max_chunk_length',
  ];

  @override
  Future<SearchConfiguration> load() async {
    final stored = await _loadAppSetting(searchConfigurationSettingKey);
    if (stored != null) {
      final configuration = _decode(stored);
      await _removeLegacyKeys();
      return configuration;
    }

    final migrated = _readLegacyConfiguration();
    await _write(migrated);
    await _removeLegacyKeys();
    return migrated;
  }

  @override
  Future<SearchConfiguration> save(SearchConfiguration desired) async {
    final current = await load();
    final saved = current.forSavedUpdate(desired);
    await _write(saved);
    await _removeLegacyKeys();
    return saved;
  }

  SearchConfiguration _readLegacyConfiguration() {
    final defaults = SearchConfiguration.defaults();
    final scopeSecretNote = _legacyBool(
      'search.scope.include_secret_note',
      defaults.includeSecretNote,
    );
    final indexSecretNote = _legacyBool(
      'search.index.include_secret_notes',
      true,
    );
    final scopeNoteBody = _legacyBool(
      'search.scope.include_note_body',
      defaults.includeNoteBody,
    );
    final indexNoteBody = _legacyBool('search.index.include_note_body', true);
    final chunkLength = _preferences.get('search.index.max_chunk_length');

    return SearchConfiguration(
      formatVersion: searchConfigurationFormatVersion,
      configurationEpoch: 1,
      includeTitle: _legacyBool(
        'search.scope.include_title',
        defaults.includeTitle,
      ),
      includeSecretNote: scopeSecretNote && indexSecretNote,
      includePasswordField: _legacyBool(
        'search.scope.include_password_field',
        defaults.includePasswordField,
      ),
      includeUsername: _legacyBool(
        'search.scope.include_username',
        defaults.includeUsername,
      ),
      includeUrl: _legacyBool('search.scope.include_url', defaults.includeUrl),
      includeTags: _legacyBool(
        'search.scope.include_tags',
        defaults.includeTags,
      ),
      includeNoteBody: scopeNoteBody && indexNoteBody,
      allowLocalEmbedding: _legacyBool(
        'search.scope.allow_local_embedding',
        defaults.allowLocalEmbedding,
      ),
      allowExternalProviderAccess: _legacyBool(
        'search.scope.allow_external_provider_access',
        defaults.allowExternalProviderAccess,
      ),
      autoIndexEnabled: _legacyBool(
        'search.index.auto_index_enabled',
        defaults.autoIndexEnabled,
      ),
      maxChunkLength:
          chunkLength is int &&
              supportedSearchChunkLengths.contains(chunkLength)
          ? chunkLength
          : defaults.maxChunkLength,
    );
  }

  bool _legacyBool(String key, bool fallback) {
    final value = _preferences.get(key);
    if (value == null) {
      return fallback;
    }
    return value is bool ? value : false;
  }

  SearchConfiguration _decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Invalid search configuration.');
    }
    return SearchConfiguration.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> _write(SearchConfiguration configuration) {
    return _saveAppSetting(
      key: searchConfigurationSettingKey,
      value: jsonEncode(configuration.toJson()),
    );
  }

  Future<void> _removeLegacyKeys() async {
    for (final key in _legacyKeys) {
      await _preferences.remove(key);
    }
  }
}
