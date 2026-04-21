import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_repository.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/search/infrastructure/sqlite_embedding_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesSearchRepository implements SearchRepository {
  SharedPreferencesSearchRepository({
    required SharedPreferences preferences,
    required SqliteEmbeddingRepository embeddingRepository,
  })  : _preferences = preferences,
        _embeddingRepository = embeddingRepository;

  final SharedPreferences _preferences;
  final SqliteEmbeddingRepository _embeddingRepository;

  static const _includeTitleKey = 'search.scope.include_title';
  static const _includeSecretNoteKey = 'search.scope.include_secret_note';
  static const _includePasswordFieldKey = 'search.scope.include_password_field';
  static const _includeUsernameKey = 'search.scope.include_username';
  static const _includeUrlKey = 'search.scope.include_url';
  static const _includeTagsKey = 'search.scope.include_tags';
  static const _includeNoteBodyKey = 'search.scope.include_note_body';
  static const _allowLocalEmbeddingKey = 'search.scope.allow_local_embedding';
  static const _allowExternalProviderAccessKey = 'search.scope.allow_external_provider_access';

  @override
  Future<SearchScopeConfig> loadScopeConfig() async {
    return SearchScopeConfig(
      includeTitle: _preferences.getBool(_includeTitleKey) ?? true,
      includeSecretNote: _preferences.getBool(_includeSecretNoteKey) ?? true,
      includePasswordField: _preferences.getBool(_includePasswordFieldKey) ?? false,
      includeUsername: _preferences.getBool(_includeUsernameKey) ?? true,
      includeUrl: _preferences.getBool(_includeUrlKey) ?? true,
      includeTags: _preferences.getBool(_includeTagsKey) ?? true,
      includeNoteBody: _preferences.getBool(_includeNoteBodyKey) ?? true,
      allowLocalEmbedding: _preferences.getBool(_allowLocalEmbeddingKey) ?? true,
      allowExternalProviderAccess: _preferences.getBool(_allowExternalProviderAccessKey) ?? false,
    );
  }

  @override
  Future<void> saveScopeConfig(SearchScopeConfig config) async {
    await _preferences.setBool(_includeTitleKey, config.includeTitle);
    await _preferences.setBool(_includeSecretNoteKey, config.includeSecretNote);
    await _preferences.setBool(_includePasswordFieldKey, config.includePasswordField);
    await _preferences.setBool(_includeUsernameKey, config.includeUsername);
    await _preferences.setBool(_includeUrlKey, config.includeUrl);
    await _preferences.setBool(_includeTagsKey, config.includeTags);
    await _preferences.setBool(_includeNoteBodyKey, config.includeNoteBody);
    await _preferences.setBool(_allowLocalEmbeddingKey, config.allowLocalEmbedding);
    await _preferences.setBool(_allowExternalProviderAccessKey, config.allowExternalProviderAccess);
  }

  @override
  Future<List<EmbeddingChunk>> getChunksBySource(
    String sourceId,
    SearchSourceType sourceType,
    String modelId,
  ) {
    return _embeddingRepository.getChunksBySource(sourceId, sourceType, modelId);
  }

  @override
  Future<void> removeChunksBySource(String sourceId, SearchSourceType sourceType) {
    return _embeddingRepository.removeChunksBySource(sourceId, sourceType);
  }

  @override
  Future<void> upsertEmbeddingChunks(List<EmbeddingChunk> chunks) {
    return _embeddingRepository.upsertEmbeddingChunks(chunks);
  }
}
