import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/search/application/search_index_chunker.dart';
import 'package:note_secret_search/features/search/application/search_index_projector.dart';
import 'package:note_secret_search/features/search/domain/effective_search_policy.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_index_document.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

void main() {
  test('secret projection emits real fields and never decrypts password', () {
    final crypto = _RecordingCryptoService()
      ..allow(EncryptedDatabaseField.secretUsername, 'alice')
      ..allow(EncryptedDatabaseField.secretWebsiteUrl, 'https://example.test')
      ..allow(EncryptedDatabaseField.secretNote, 'private note');
    final projector = SearchIndexProjector(cryptoService: crypto);
    final policy = EffectiveSearchPolicy(
      SearchConfiguration.defaults().copyWith(includePasswordField: true),
    );

    final document = projector.projectSecret(
      _secret(tags: const <String>[' Work ', 'work', 'Personal']),
      policy,
    );

    expect(
      document.fields.map((field) => field.field),
      const <SearchSourceField>[
        SearchSourceField.secretTitle,
        SearchSourceField.secretUsername,
        SearchSourceField.secretWebsiteUrl,
        SearchSourceField.secretNote,
        SearchSourceField.secretTags,
      ],
    );
    expect(document.fields.last.values, const <String>['Personal', 'Work']);
    expect(
      crypto.decryptedFields,
      isNot(contains(EncryptedDatabaseField.secretPassword)),
    );
  });

  test('note projection keeps summary and body as distinct fields', () {
    final crypto = _RecordingCryptoService()
      ..allow(EncryptedDatabaseField.noteSummary, 'Summary')
      ..allow(EncryptedDatabaseField.noteContent, 'Body');
    final projector = SearchIndexProjector(cryptoService: crypto);

    final document = projector.projectNote(
      _note(),
      EffectiveSearchPolicy(SearchConfiguration.defaults()),
    );

    expect(
      document.fields.map((field) => field.field),
      const <SearchSourceField>[
        SearchSourceField.noteTitle,
        SearchSourceField.noteSummary,
        SearchSourceField.noteBody,
        SearchSourceField.noteTags,
      ],
    );
  });

  test('chunker resets indexes by field and keeps each tag independent', () {
    final crypto = _RecordingCryptoService()
      ..allow(EncryptedDatabaseField.noteSummary, 'Summary')
      ..allow(
        EncryptedDatabaseField.noteContent,
        'first paragraph\n\nsecond paragraph',
      );
    final document = SearchIndexProjector(cryptoService: crypto).projectNote(
      _note(tags: const <String>['beta', 'Alpha']),
      EffectiveSearchPolicy(SearchConfiguration.defaults()),
    );

    final chunks = const SearchIndexChunker().chunk(
      document,
      maxChunkLength: 160,
    );

    expect(
      chunks
          .where((chunk) => chunk.field == SearchSourceField.noteTags)
          .map((chunk) => (chunk.fieldChunkIndex, chunk.text)),
      const <(int, String)>[(0, 'Alpha'), (1, 'beta')],
    );
    expect(
      chunks
          .where((chunk) => chunk.field == SearchSourceField.noteBody)
          .map((chunk) => chunk.fieldChunkIndex),
      const <int>[0],
    );
    expect(
      chunks
          .where((chunk) => chunk.field == SearchSourceField.noteSummary)
          .single
          .fieldChunkIndex,
      0,
    );
  });

  test('hard splitting preserves Unicode scalar boundaries', () {
    final runes = List<String>.generate(161, (_) => '😀').join();
    final document = SearchIndexDocument(
      sourceKey: const SearchSourceKey.note('note-1'),
      vaultId: 'default',
      title: 'Unicode',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      fields: <SearchIndexFieldContent>[
        SearchIndexFieldContent(
          field: SearchSourceField.noteBody,
          values: <String>[runes],
        ),
      ],
    );

    final chunks = const SearchIndexChunker().chunk(
      document,
      maxChunkLength: 160,
    );

    expect(chunks, hasLength(2));
    expect(chunks.first.text.runes.length, 160);
    expect(chunks.last.text, '😀');
  });
}

class _RecordingCryptoService implements CryptoService {
  final Map<EncryptedDatabaseField, String> _values =
      <EncryptedDatabaseField, String>{};
  final List<EncryptedDatabaseField> decryptedFields =
      <EncryptedDatabaseField>[];

  _RecordingCryptoService allow(EncryptedDatabaseField field, String value) {
    _values[field] = value;
    return this;
  }

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    final field = EncryptedDatabaseField.values.firstWhere(
      (candidate) =>
          candidate.table == context.table &&
          candidate.column == context.column,
    );
    decryptedFields.add(field);
    return _values[field] ?? '';
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    throw UnimplementedError();
  }
}

SecretItem _secret({List<String> tags = const <String>[]}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return SecretItem(
    id: 'secret-1',
    vaultId: 'default',
    title: 'Account',
    usernameCiphertext: const <int>[1],
    passwordCiphertext: const <int>[2],
    websiteUrlCiphertext: const <int>[3],
    noteCiphertext: const <int>[4],
    tags: tags,
    categoryId: null,
    favorite: false,
    createdAt: now,
    updatedAt: now,
  );
}

NoteItem _note({List<String> tags = const <String>['tag']}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1);
  return NoteItem(
    id: 'note-1',
    vaultId: 'default',
    title: 'Note',
    contentCiphertext: const <int>[1],
    summaryCacheCiphertext: const <int>[2],
    tags: tags,
    categoryId: null,
    favorite: false,
    createdAt: now,
    updatedAt: now,
  );
}
