import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/search_evidence.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

class SearchService {
  const SearchService({required CryptoService cryptoService})
    : _cryptoService = cryptoService;

  final CryptoService _cryptoService;

  List<SearchResultItem> search({
    required String activeVaultId,
    required String query,
    required SearchConfiguration configuration,
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <SearchResultItem>[];
    }
    final policy = EffectiveSearchPolicy(configuration);
    final results = <SearchResultItem>[
      ..._searchSecrets(
        normalizedQuery,
        policy,
        secrets.where(
          (item) => item.vaultId == activeVaultId && item.deletedAt == null,
        ),
      ),
      ..._searchNotes(
        normalizedQuery,
        policy,
        notes.where(
          (item) => item.vaultId == activeVaultId && item.deletedAt == null,
        ),
      ),
    ];
    results.sort(
      (left, right) => _compareResults(normalizedQuery, left, right),
    );
    return List<SearchResultItem>.unmodifiable(results.take(200));
  }

  Future<List<SearchResultItem>> searchCorpus({
    required String activeVaultId,
    required String query,
    required SearchConfiguration configuration,
    required SearchCorpusReader corpus,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <SearchResultItem>[];
    }
    final policy = EffectiveSearchPolicy(configuration);
    final results = <SearchResultItem>[];

    String? afterSecretId;
    while (true) {
      final page = await corpus.secretPage(
        vaultId: activeVaultId,
        afterId: afterSecretId,
      );
      if (page.isEmpty) {
        break;
      }
      _addTopKeywordResults(
        results,
        _searchSecrets(normalizedQuery, policy, page),
        normalizedQuery,
      );
      final nextId = page.last.id;
      if (afterSecretId != null && nextId.compareTo(afterSecretId!) <= 0) {
        throw StateError('Secret search corpus page cursor did not advance.');
      }
      afterSecretId = nextId;
      if (page.length < searchSourcePageSize) {
        break;
      }
    }

    String? afterNoteId;
    while (true) {
      final page = await corpus.notePage(
        vaultId: activeVaultId,
        afterId: afterNoteId,
      );
      if (page.isEmpty) {
        break;
      }
      _addTopKeywordResults(
        results,
        _searchNotes(normalizedQuery, policy, page),
        normalizedQuery,
      );
      final nextId = page.last.id;
      if (afterNoteId != null && nextId.compareTo(afterNoteId!) <= 0) {
        throw StateError('Note search corpus page cursor did not advance.');
      }
      afterNoteId = nextId;
      if (page.length < searchSourcePageSize) {
        break;
      }
    }

    return List<SearchResultItem>.unmodifiable(results.take(200));
  }

  List<SearchResultItem> _searchSecrets(
    String query,
    EffectiveSearchPolicy policy,
    Iterable<SecretItem> secrets,
  ) {
    final results = <SearchResultItem>[];
    for (final item in secrets) {
      final hits = <SearchSourceField>[];
      final title = item.title;
      if (_fieldMatches(query, title, policy, SearchSourceField.secretTitle)) {
        hits.add(SearchSourceField.secretTitle);
      }
      final username = _decryptIfAllowed(
        item.usernameCiphertext,
        item.id,
        EncryptedDatabaseField.secretUsername,
        SearchSourceField.secretUsername,
        policy,
      );
      if (_matches(query, username)) {
        hits.add(SearchSourceField.secretUsername);
      }
      final website = _decryptIfAllowed(
        item.websiteUrlCiphertext,
        item.id,
        EncryptedDatabaseField.secretWebsiteUrl,
        SearchSourceField.secretWebsiteUrl,
        policy,
      );
      if (_matches(query, website)) {
        hits.add(SearchSourceField.secretWebsiteUrl);
      }
      final note = _decryptIfAllowed(
        item.noteCiphertext,
        item.id,
        EncryptedDatabaseField.secretNote,
        SearchSourceField.secretNote,
        policy,
      );
      if (_matches(query, note)) {
        hits.add(SearchSourceField.secretNote);
      }
      final password = _decryptIfAllowed(
        item.passwordCiphertext,
        item.id,
        EncryptedDatabaseField.secretPassword,
        SearchSourceField.secretPassword,
        policy,
      );
      if (_matches(query, password)) {
        hits.add(SearchSourceField.secretPassword);
      }
      if (_fieldMatches(
        query,
        item.tags.join(' '),
        policy,
        SearchSourceField.secretTags,
      )) {
        hits.add(SearchSourceField.secretTags);
      }
      if (hits.isEmpty) {
        continue;
      }
      results.add(
        SearchResultItem(
          id: item.id,
          type: SearchResultType.secret,
          title: title,
          preview: username.isNotEmpty ? username : note,
          tags: item.tags,
          favorite: item.favorite,
          updatedAt: item.updatedAt,
          keywordHitFields: List<SearchSourceField>.unmodifiable(hits),
          evidence: _keywordEvidence(hits),
        ),
      );
    }
    return results;
  }

  List<SearchResultItem> _searchNotes(
    String query,
    EffectiveSearchPolicy policy,
    Iterable<NoteItem> notes,
  ) {
    final results = <SearchResultItem>[];
    for (final item in notes) {
      final hits = <SearchSourceField>[];
      if (_fieldMatches(
        query,
        item.title,
        policy,
        SearchSourceField.noteTitle,
      )) {
        hits.add(SearchSourceField.noteTitle);
      }
      final summary = _decryptIfAllowed(
        item.summaryCacheCiphertext,
        item.id,
        EncryptedDatabaseField.noteSummary,
        SearchSourceField.noteSummary,
        policy,
      );
      if (_matches(query, summary)) {
        hits.add(SearchSourceField.noteSummary);
      }
      final body = _decryptIfAllowed(
        item.contentCiphertext,
        item.id,
        EncryptedDatabaseField.noteContent,
        SearchSourceField.noteBody,
        policy,
      );
      if (_matches(query, body)) {
        hits.add(SearchSourceField.noteBody);
      }
      if (_fieldMatches(
        query,
        item.tags.join(' '),
        policy,
        SearchSourceField.noteTags,
      )) {
        hits.add(SearchSourceField.noteTags);
      }
      if (hits.isEmpty) {
        continue;
      }
      results.add(
        SearchResultItem(
          id: item.id,
          type: SearchResultType.note,
          title: item.title,
          preview: summary.isNotEmpty ? summary : body,
          tags: item.tags,
          favorite: item.favorite,
          updatedAt: item.updatedAt,
          keywordHitFields: List<SearchSourceField>.unmodifiable(hits),
          evidence: _keywordEvidence(hits),
        ),
      );
    }
    return results;
  }

  String _decryptIfAllowed(
    List<int>? ciphertext,
    String rowId,
    EncryptedDatabaseField encryptedField,
    SearchSourceField sourceField,
    EffectiveSearchPolicy policy,
  ) {
    if (!policy.allows(sourceField, SearchOperation.keyword)) {
      return '';
    }
    return _cryptoService.decryptField(
      ciphertext,
      field: encryptedField,
      rowId: rowId,
    );
  }

  bool _fieldMatches(
    String query,
    String value,
    EffectiveSearchPolicy policy,
    SearchSourceField field,
  ) {
    return policy.allows(field, SearchOperation.keyword) &&
        _matches(query, value);
  }

  bool _matches(String query, String value) {
    return value.isNotEmpty && value.toLowerCase().contains(query);
  }

  List<SearchEvidence> _keywordEvidence(List<SearchSourceField> fields) {
    return List<SearchEvidence>.unmodifiable(
      fields.map((field) => SearchEvidence.keyword(sourceField: field)),
    );
  }

  int _compareResults(
    String query,
    SearchResultItem left,
    SearchResultItem right,
  ) {
    var result = _queryAffinity(
      query,
      right,
    ).compareTo(_queryAffinity(query, left));
    result = result != 0
        ? result
        : _fieldQuality(right).compareTo(_fieldQuality(left));
    result = result != 0
        ? result
        : _fieldPriority(right).compareTo(_fieldPriority(left));
    result = result != 0
        ? result
        : (right.favorite ? 1 : 0).compareTo(left.favorite ? 1 : 0);
    result = result != 0 ? result : right.updatedAt.compareTo(left.updatedAt);
    result = result != 0 ? result : left.type.index.compareTo(right.type.index);
    return result != 0 ? result : left.id.compareTo(right.id);
  }

  void _addTopKeywordResults(
    List<SearchResultItem> results,
    Iterable<SearchResultItem> incoming,
    String query,
  ) {
    results.addAll(incoming);
    results.sort((left, right) => _compareResults(query, left, right));
    if (results.length > 200) {
      results.removeRange(200, results.length);
    }
  }

  int _queryAffinity(String query, SearchResultItem item) {
    if (query.contains('@') &&
        item.keywordHitFields.contains(SearchSourceField.secretUsername)) {
      return 1;
    }
    if ((query.contains('://') || query.contains('.') || query.contains('/')) &&
        item.keywordHitFields.contains(SearchSourceField.secretWebsiteUrl)) {
      return 1;
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{1,24}$').hasMatch(query) &&
        item.keywordHitFields.any(
          (field) =>
              field == SearchSourceField.secretTags ||
              field == SearchSourceField.noteTags,
        )) {
      return 1;
    }
    return 0;
  }

  int _fieldQuality(SearchResultItem item) {
    return item.keywordHitFields.any(
          (field) =>
              field == SearchSourceField.secretTitle ||
              field == SearchSourceField.noteTitle ||
              field == SearchSourceField.secretUsername ||
              field == SearchSourceField.noteSummary,
        )
        ? 2
        : 1;
  }

  int _fieldPriority(SearchResultItem item) {
    var best = 0;
    for (final field in item.keywordHitFields) {
      final priority = switch (field) {
        SearchSourceField.secretTitle || SearchSourceField.noteTitle => 6,
        SearchSourceField.secretUsername || SearchSourceField.noteSummary => 5,
        SearchSourceField.secretWebsiteUrl || SearchSourceField.secretNote => 4,
        SearchSourceField.secretTags || SearchSourceField.noteTags => 3,
        SearchSourceField.noteBody => 2,
        SearchSourceField.secretPassword => 1,
      };
      if (priority > best) {
        best = priority;
      }
    }
    return best;
  }
}
