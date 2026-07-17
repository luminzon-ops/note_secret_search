import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/domain/search_result_item.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

class SearchService {
  const SearchService({required CryptoService cryptoService})
    : _cryptoService = cryptoService;

  final CryptoService _cryptoService;

  List<SearchResultItem> search({
    required String query,
    required SearchScopeConfig scope,
    required List<SecretItem> secrets,
    required List<NoteItem> notes,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <SearchResultItem>[];
    }

    final results = <SearchResultItem>[
      ..._searchSecrets(normalizedQuery, scope, secrets),
      ..._searchNotes(normalizedQuery, scope, notes),
    ];

    results.sort((a, b) {
      final favoriteSort = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
      if (favoriteSort != 0) {
        return favoriteSort;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return results;
  }

  List<SearchResultItem> _searchSecrets(
    String query,
    SearchScopeConfig scope,
    List<SecretItem> secrets,
  ) {
    final results = <SearchResultItem>[];
    for (final item in secrets) {
      final title = item.title;
      final username = scope.includeUsername
          ? _cryptoService.decryptField(
              item.usernameCiphertext,
              field: EncryptedDatabaseField.secretUsername,
              rowId: item.id,
            )
          : '';
      final website = scope.includeUrl
          ? _cryptoService.decryptField(
              item.websiteUrlCiphertext,
              field: EncryptedDatabaseField.secretWebsiteUrl,
              rowId: item.id,
            )
          : '';
      final note = scope.includeSecretNote
          ? _cryptoService.decryptField(
              item.noteCiphertext,
              field: EncryptedDatabaseField.secretNote,
              rowId: item.id,
            )
          : '';
      final password = scope.includePasswordField
          ? _cryptoService.decryptField(
              item.passwordCiphertext,
              field: EncryptedDatabaseField.secretPassword,
              rowId: item.id,
            )
          : '';

      final haystacks = <String>[
        if (scope.includeTitle) title,
        if (scope.includeUsername) username,
        if (scope.includeUrl) website,
        if (scope.includeSecretNote) note,
        if (scope.includePasswordField) password,
        if (scope.includeTags) item.tags.join(' '),
      ];

      if (_matches(query, haystacks)) {
        results.add(
          SearchResultItem(
            id: item.id,
            type: SearchResultType.secret,
            title: title,
            preview: username.isNotEmpty ? username : note,
            tags: item.tags,
            favorite: item.favorite,
            updatedAt: item.updatedAt,
          ),
        );
      }
    }
    return results;
  }

  List<SearchResultItem> _searchNotes(
    String query,
    SearchScopeConfig scope,
    List<NoteItem> notes,
  ) {
    final results = <SearchResultItem>[];
    for (final item in notes) {
      final title = item.title;
      final summary = scope.includeNoteBody
          ? _cryptoService.decryptField(
              item.summaryCacheCiphertext,
              field: EncryptedDatabaseField.noteSummary,
              rowId: item.id,
            )
          : '';
      final content = scope.includeNoteBody
          ? _cryptoService.decryptField(
              item.contentCiphertext,
              field: EncryptedDatabaseField.noteContent,
              rowId: item.id,
            )
          : '';

      final haystacks = <String>[
        if (scope.includeTitle) title,
        if (scope.includeNoteBody) content,
        if (scope.includeNoteBody) summary,
        if (scope.includeTags) item.tags.join(' '),
      ];

      if (_matches(query, haystacks)) {
        results.add(
          SearchResultItem(
            id: item.id,
            type: SearchResultType.note,
            title: title,
            preview: summary.isNotEmpty ? summary : content,
            tags: item.tags,
            favorite: item.favorite,
            updatedAt: item.updatedAt,
          ),
        );
      }
    }
    return results;
  }

  bool _matches(String query, List<String> haystacks) {
    return haystacks.any((value) => value.toLowerCase().contains(query));
  }
}
