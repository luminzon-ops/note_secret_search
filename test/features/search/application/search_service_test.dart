import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/application/search_service.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/search/domain/search_corpus_reader.dart';
import 'package:note_secret_search/features/search/domain/semantic_search_result.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';

void main() {
  test('title-only search never decrypts excluded fields', () {
    final crypto = _RecordingCryptoService();
    final service = SearchService(cryptoService: crypto);

    final results = service.search(
      activeVaultId: 'default',
      query: 'vault',
      configuration: _configuration(includeTitle: true),
      secrets: <SecretItem>[_secret(title: 'Vault login')],
      notes: <NoteItem>[_note(title: 'Vault notes')],
    );

    expect(results.map((item) => item.id), <String>['secret-1', 'note-1']);
    expect(results.map((item) => item.preview), everyElement(isEmpty));
    expect(
      results.map((item) => item.keywordHitFields).toList(),
      const <List<SearchSourceField>>[
        <SearchSourceField>[SearchSourceField.secretTitle],
        <SearchSourceField>[SearchSourceField.noteTitle],
      ],
    );
    expect(
      results.map((item) => item.evidence).toList(),
      everyElement(
        contains(
          isA<SearchEvidence>()
              .having(
                (evidence) => evidence.kind,
                'kind',
                SearchEvidenceKind.keyword,
              )
              .having((evidence) => evidence.summary, 'summary', isEmpty),
        ),
      ),
    );
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
      activeVaultId: 'default',
      query: 'alice',
      configuration: _configuration(includeUsername: true),
      secrets: <SecretItem>[_secret(title: 'Account')],
      notes: const <NoteItem>[],
    );

    expect(results.single.id, 'secret-1');
    expect(results.single.preview, 'alice');
    expect(results.single.keywordHitFields, const <SearchSourceField>[
      SearchSourceField.secretUsername,
    ]);
    expect(
      crypto.decryptedContexts.map(
        (context) => '${context.table}/${context.rowId}/${context.column}',
      ),
      <String>['secret_items/secret-1/username_ciphertext'],
    );
  });

  test(
    'keyword search rejects deleted and other-vault sources at the service boundary',
    () {
      final crypto = _RecordingCryptoService();
      final service = SearchService(cryptoService: crypto);

      final results = service.search(
        activeVaultId: 'default',
        query: 'vault',
        configuration: _configuration(includeTitle: true),
        secrets: <SecretItem>[
          _secret(title: 'Vault live', id: 'live', vaultId: 'default'),
          _secret(title: 'Vault other', id: 'other', vaultId: 'other-vault'),
          _secret(
            title: 'Vault deleted',
            id: 'deleted',
            vaultId: 'default',
            deletedAt: DateTime(2026, 7, 20),
          ),
        ],
        notes: const <NoteItem>[],
      );

      expect(results.map((item) => item.id), const <String>['live']);
    },
  );

  test(
    'keyword candidate cap preserves high-affinity username hits after 200 results',
    () {
      final service = SearchService(cryptoService: const _WideCryptoService());
      final now = DateTime(2026, 7, 20);
      final secrets = <SecretItem>[
        for (var index = 0; index < 200; index++)
          SecretItem(
            id: 'note-hit-${index.toString().padLeft(3, '0')}',
            vaultId: 'default',
            title: 'Low priority $index',
            usernameCiphertext: 'other'.codeUnits,
            passwordCiphertext: 'password'.codeUnits,
            websiteUrlCiphertext: 'https://example.test'.codeUnits,
            noteCiphertext: 'alice@example.test'.codeUnits,
            tags: const <String>[],
            categoryId: null,
            favorite: false,
            createdAt: now,
            updatedAt: now,
          ),
        SecretItem(
          id: 'username-hit',
          vaultId: 'default',
          title: 'Older high affinity',
          usernameCiphertext: 'alice@example.test'.codeUnits,
          passwordCiphertext: 'password'.codeUnits,
          websiteUrlCiphertext: 'https://example.test'.codeUnits,
          noteCiphertext: 'other'.codeUnits,
          tags: const <String>[],
          categoryId: null,
          favorite: false,
          createdAt: now.subtract(const Duration(days: 2)),
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
      ];

      final results = service.search(
        activeVaultId: 'default',
        query: 'alice@example.test',
        configuration: _configuration(
          includeSecretNote: true,
          includeUsername: true,
        ),
        secrets: secrets,
        notes: const <NoteItem>[],
      );

      expect(results, hasLength(200));
      expect(results.first.id, 'username-hit');
    },
  );

  test(
    'paged keyword corpus keeps bounded pages and late high-affinity hits',
    () async {
      final now = DateTime(2026, 7, 20);
      final repository = _PagedSecretRepository(<SecretItem>[
        for (var index = 0; index < 299; index++)
          _wideSecret(
            id: 'secret-${index.toString().padLeft(3, '0')}',
            username: 'other',
            note: 'alice@example.test',
            updatedAt: now,
          ),
        _wideSecret(
          id: 'secret-299',
          username: 'alice@example.test',
          note: 'other',
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
      ]);
      final service = SearchService(cryptoService: const _WideCryptoService());

      final results = await service.searchCorpus(
        activeVaultId: 'default',
        query: 'alice@example.test',
        configuration: _configuration(
          includeSecretNote: true,
          includeUsername: true,
        ),
        corpus: SearchCorpusReader(
          secretRepository: repository,
          noteRepository: _EmptyNoteRepository(),
        ),
      );

      expect(repository.pageSizes, const <int>[128, 128, 44]);
      expect(results, hasLength(200));
      expect(results.first.id, 'secret-299');
    },
  );
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

class _WideCryptoService implements CryptoService {
  const _WideCryptoService();

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    return ciphertext == null ? '' : String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    return plaintext == null ? null : Uint8List.fromList(plaintext.codeUnits);
  }
}

class _PagedSecretRepository implements SecretRepository, SecretSearchReader {
  _PagedSecretRepository(this.items);

  final List<SecretItem> items;
  final List<int> pageSizes = <int>[];

  @override
  Future<List<SecretItem>> listByVaultPage(
    String vaultId, {
    String? afterId,
    int limit = searchSourcePageSize,
  }) async {
    final page = items
        .where(
          (item) =>
              item.vaultId == vaultId &&
              item.deletedAt == null &&
              (afterId == null || item.id.compareTo(afterId) > 0),
        )
        .take(limit)
        .toList(growable: false);
    pageSizes.add(page.length);
    return page;
  }

  @override
  Future<List<SecretItem>> listByVault(String vaultId) {
    throw StateError('unbounded secret load');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyNoteRepository implements NoteRepository, NoteSearchReader {
  @override
  Future<List<NoteItem>> listByVaultPage(
    String vaultId, {
    String? afterId,
    int limit = searchSourcePageSize,
  }) async {
    return const <NoteItem>[];
  }

  @override
  Future<List<NoteItem>> listByVault(String vaultId) {
    throw StateError('unbounded note load');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SearchConfiguration _configuration({
  bool includeTitle = false,
  bool includeSecretNote = false,
  bool includePasswordField = false,
  bool includeUsername = false,
  bool includeUrl = false,
  bool includeTags = false,
  bool includeNoteBody = false,
}) {
  return SearchConfiguration.defaults().copyWith(
    includeTitle: includeTitle,
    includeSecretNote: includeSecretNote,
    includePasswordField: includePasswordField,
    includeUsername: includeUsername,
    includeUrl: includeUrl,
    includeTags: includeTags,
    includeNoteBody: includeNoteBody,
    allowLocalEmbedding: false,
  );
}

SecretItem _secret({
  required String title,
  String id = 'secret-1',
  String vaultId = 'default',
  DateTime? deletedAt,
}) {
  final now = DateTime(2026, 7, 16);
  return SecretItem(
    id: id,
    vaultId: vaultId,
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
    deletedAt: deletedAt,
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

SecretItem _wideSecret({
  required String id,
  required String username,
  required String note,
  required DateTime updatedAt,
}) {
  return SecretItem(
    id: id,
    vaultId: 'default',
    title: id,
    usernameCiphertext: username.codeUnits,
    passwordCiphertext: 'password'.codeUnits,
    websiteUrlCiphertext: 'https://example.test'.codeUnits,
    noteCiphertext: note.codeUnits,
    tags: const <String>[],
    categoryId: null,
    favorite: false,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}
