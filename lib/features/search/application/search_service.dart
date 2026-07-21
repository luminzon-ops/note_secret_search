import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
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
    results.sort(_compareResults);
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

  int _compareResults(SearchResultItem left, SearchResultItem right) {
    var result = (right.favorite ? 1 : 0).compareTo(left.favorite ? 1 : 0);
    result = result != 0 ? result : right.updatedAt.compareTo(left.updatedAt);
    result = result != 0 ? result : left.type.index.compareTo(right.type.index);
    return result != 0 ? result : left.id.compareTo(right.id);
  }
}
