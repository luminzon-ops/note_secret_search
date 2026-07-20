import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/security/search_index_fingerprint.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_index_document.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

class SearchIndexProjector {
  const SearchIndexProjector({required CryptoService cryptoService})
    : _cryptoService = cryptoService;

  final CryptoService _cryptoService;

  SearchIndexDocument projectSecret(
    SecretItem item,
    EffectiveSearchPolicy policy,
  ) {
    return SearchIndexDocument(
      sourceKey: SearchSourceKey.secret(item.id),
      vaultId: item.vaultId,
      title: item.title,
      updatedAt: item.updatedAt,
      fields: <SearchIndexFieldContent>[
        if (policy.allows(
          SearchSourceField.secretTitle,
          SearchOperation.indexing,
        ))
          _single(SearchSourceField.secretTitle, item.title),
        if (policy.allows(
          SearchSourceField.secretUsername,
          SearchOperation.indexing,
        ))
          _single(
            SearchSourceField.secretUsername,
            _decrypt(
              item.usernameCiphertext,
              EncryptedDatabaseField.secretUsername,
              item.id,
            ),
          ),
        if (policy.allows(
          SearchSourceField.secretWebsiteUrl,
          SearchOperation.indexing,
        ))
          _single(
            SearchSourceField.secretWebsiteUrl,
            _decrypt(
              item.websiteUrlCiphertext,
              EncryptedDatabaseField.secretWebsiteUrl,
              item.id,
            ),
          ),
        if (policy.allows(
          SearchSourceField.secretNote,
          SearchOperation.indexing,
        ))
          _single(
            SearchSourceField.secretNote,
            _decrypt(
              item.noteCiphertext,
              EncryptedDatabaseField.secretNote,
              item.id,
            ),
          ),
        if (policy.allows(
          SearchSourceField.secretTags,
          SearchOperation.indexing,
        ))
          SearchIndexFieldContent(
            field: SearchSourceField.secretTags,
            values: canonicalTags(item.tags),
          ),
      ],
    );
  }

  SearchIndexDocument projectNote(NoteItem item, EffectiveSearchPolicy policy) {
    return SearchIndexDocument(
      sourceKey: SearchSourceKey.note(item.id),
      vaultId: item.vaultId,
      title: item.title,
      updatedAt: item.updatedAt,
      fields: <SearchIndexFieldContent>[
        if (policy.allows(
          SearchSourceField.noteTitle,
          SearchOperation.indexing,
        ))
          _single(SearchSourceField.noteTitle, item.title),
        if (policy.allows(
          SearchSourceField.noteSummary,
          SearchOperation.indexing,
        ))
          _single(
            SearchSourceField.noteSummary,
            _decrypt(
              item.summaryCacheCiphertext,
              EncryptedDatabaseField.noteSummary,
              item.id,
            ),
          ),
        if (policy.allows(SearchSourceField.noteBody, SearchOperation.indexing))
          _single(
            SearchSourceField.noteBody,
            _decrypt(
              item.contentCiphertext,
              EncryptedDatabaseField.noteContent,
              item.id,
            ),
          ),
        if (policy.allows(SearchSourceField.noteTags, SearchOperation.indexing))
          SearchIndexFieldContent(
            field: SearchSourceField.noteTags,
            values: canonicalTags(item.tags),
          ),
      ],
    );
  }

  SearchIndexFieldContent _single(SearchSourceField field, String value) {
    return SearchIndexFieldContent(field: field, values: <String>[value]);
  }

  String _decrypt(
    List<int>? ciphertext,
    EncryptedDatabaseField field,
    String rowId,
  ) {
    return _cryptoService.decryptField(ciphertext, field: field, rowId: rowId);
  }
}
