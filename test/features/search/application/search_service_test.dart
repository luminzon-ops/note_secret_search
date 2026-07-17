import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_service.dart';
import 'package:note_secret_search/features/search/domain/search_scope.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

void main() {
  test('title-only search never decrypts excluded fields', () {
    final crypto = _RecordingCryptoService();
    final service = SearchService(cryptoService: crypto);

    final results = service.search(
      query: 'vault',
      scope: _scope(includeTitle: true),
      secrets: <SecretItem>[_secret(title: 'Vault login')],
      notes: <NoteItem>[_note(title: 'Vault notes')],
    );

    expect(results.map((item) => item.id), <String>['secret-1', 'note-1']);
    expect(results.map((item) => item.preview), everyElement(isEmpty));
    expect(crypto.decryptedContexts, isEmpty);
  });

  test('username search decrypts only the exact scoped field context', () {
    final crypto = _RecordingCryptoService()
      ..allow(
        EncryptedDatabaseField.secretUsername.contextFor('secret-1'),
        'alice',
      );
    final service = SearchService(cryptoService: crypto);

    final results = service.search(
      query: 'alice',
      scope: _scope(includeUsername: true),
      secrets: <SecretItem>[_secret(title: 'Account')],
      notes: const <NoteItem>[],
    );

    expect(results.single.id, 'secret-1');
    expect(results.single.preview, 'alice');
    expect(
      crypto.decryptedContexts.map(
        (context) => '${context.table}/${context.rowId}/${context.column}',
      ),
      <String>['secret_items/secret-1/username_ciphertext'],
    );
  });
}

class _RecordingCryptoService implements CryptoService {
  final Map<String, String> _allowedValues = <String, String>{};
  final List<FieldCryptoContext> decryptedContexts = <FieldCryptoContext>[];

  void allow(FieldCryptoContext context, String plaintext) {
    _allowedValues[_key(context)] = plaintext;
  }

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    decryptedContexts.add(context);
    final plaintext = _allowedValues[_key(context)];
    if (plaintext == null) {
      throw StateError('Unexpected field decryption: ${_key(context)}');
    }
    return plaintext;
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    throw UnimplementedError();
  }

  String _key(FieldCryptoContext context) {
    return '${context.table}/${context.rowId}/${context.column}';
  }
}

SearchScopeConfig _scope({
  bool includeTitle = false,
  bool includeSecretNote = false,
  bool includePasswordField = false,
  bool includeUsername = false,
  bool includeUrl = false,
  bool includeTags = false,
  bool includeNoteBody = false,
}) {
  return SearchScopeConfig(
    includeTitle: includeTitle,
    includeSecretNote: includeSecretNote,
    includePasswordField: includePasswordField,
    includeUsername: includeUsername,
    includeUrl: includeUrl,
    includeTags: includeTags,
    includeNoteBody: includeNoteBody,
    allowLocalEmbedding: false,
    allowExternalProviderAccess: false,
  );
}

SecretItem _secret({required String title}) {
  final now = DateTime(2026, 7, 16);
  return SecretItem(
    id: 'secret-1',
    vaultId: 'default',
    title: title,
    usernameCiphertext: const <int>[1],
    passwordCiphertext: const <int>[2],
    websiteUrlCiphertext: const <int>[3],
    noteCiphertext: const <int>[4],
    tags: const <String>[],
    categoryId: null,
    favorite: false,
    createdAt: now,
    updatedAt: now,
  );
}

NoteItem _note({required String title}) {
  final now = DateTime(2026, 7, 16);
  return NoteItem(
    id: 'note-1',
    vaultId: 'default',
    title: title,
    contentCiphertext: const <int>[5],
    summaryCacheCiphertext: const <int>[6],
    tags: const <String>[],
    categoryId: null,
    favorite: false,
    createdAt: now,
    updatedAt: now,
  );
}
