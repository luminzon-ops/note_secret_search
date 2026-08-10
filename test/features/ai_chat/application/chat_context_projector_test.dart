import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/ai_chat/application/chat_context_projector.dart';
import 'package:note_secret_search/features/ai_chat/domain/chat_context_models.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/domain/search_configuration.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';

void main() {
  test(
    'manual projection rereads and emits approved plaintext fields',
    () async {
      final crypto = _RecordingCryptoService();
      final secrets = _SecretRepository(_secret);
      final notes = _NoteRepository(_note);
      final projector = RepositoryChatContextProjector(
        secretRepository: secrets,
        noteRepository: notes,
        cryptoService: crypto,
      );

      final result = await projector.projectManual(
        items: const <ChatContextItem>[
          ChatContextItem(
            id: 'secret-1',
            type: ChatContextItemType.secret,
            title: 'stale secret title',
            preview: 'stale',
            summary: 'stale',
          ),
          ChatContextItem(
            id: 'note-1',
            type: ChatContextItemType.note,
            title: 'stale note title',
            preview: 'stale',
            summary: 'stale',
          ),
        ],
        configuration: SearchConfiguration.defaults().copyWith(
          includePasswordField: true,
        ),
        target: ChatContextProjectionTarget.local,
      );

      expect(secrets.requestedIds, <String>['secret-1']);
      expect(notes.requestedIds, <String>['note-1']);
      expect(result, hasLength(2));
      expect(result.first.title, 'GitHub');
      expect(result.first.content, contains('octo-user'));
      expect(result.first.content, contains('PASSWORD_SENTINEL'));
      expect(result.first.content, contains('MFA is enabled'));
      expect(result.last.title, 'Recovery plan');
      expect(result.last.content, contains('NOTE_BODY_SENTINEL'));
    },
  );

  test(
    'external projection never decrypts or emits vault password fields',
    () async {
      final crypto = _RecordingCryptoService();
      final projector = RepositoryChatContextProjector(
        secretRepository: _SecretRepository(_secret),
        noteRepository: _NoteRepository(_note),
        cryptoService: crypto,
      );

      final result = await projector.projectManual(
        items: const <ChatContextItem>[
          ChatContextItem(
            id: 'secret-1',
            type: ChatContextItemType.secret,
            title: 'GitHub',
            preview: 'stale',
            summary: 'stale',
          ),
        ],
        configuration: SearchConfiguration.defaults().copyWith(
          includePasswordField: true,
        ),
        target: ChatContextProjectionTarget.external,
      );

      expect(result.single.content, isNot(contains('PASSWORD_SENTINEL')));
      expect(
        crypto.decryptedFields,
        isNot(contains(EncryptedDatabaseField.secretPassword)),
      );
      expect(result.single.content, contains('octo-user'));
      expect(result.single.content, contains('MFA is enabled'));
    },
  );
}

final _secret = SecretItem(
  id: 'secret-1',
  vaultId: 'vault-1',
  title: 'GitHub',
  usernameCiphertext: _bytes('octo-user'),
  passwordCiphertext: _bytes('PASSWORD_SENTINEL'),
  websiteUrlCiphertext: _bytes('https://github.example'),
  noteCiphertext: _bytes('MFA is enabled'),
  tags: const <String>['dev', 'account'],
  categoryId: null,
  favorite: false,
  createdAt: DateTime(2026, 7, 22),
  updatedAt: DateTime(2026, 7, 22),
);

final _note = NoteItem(
  id: 'note-1',
  vaultId: 'vault-1',
  title: 'Recovery plan',
  contentCiphertext: _bytes('NOTE_BODY_SENTINEL'),
  summaryCacheCiphertext: _bytes('summary'),
  tags: const <String>['recovery'],
  categoryId: null,
  favorite: false,
  createdAt: DateTime(2026, 7, 22),
  updatedAt: DateTime(2026, 7, 22),
);

Uint8List _bytes(String value) => Uint8List.fromList(value.codeUnits);

class _RecordingCryptoService implements CryptoService {
  final List<EncryptedDatabaseField> decryptedFields =
      <EncryptedDatabaseField>[];

  @override
  String decryptNullable(
    List<int>? ciphertext, {
    required FieldCryptoContext context,
  }) {
    final field = EncryptedDatabaseField.values.singleWhere(
      (candidate) =>
          candidate.table == context.table &&
          candidate.column == context.column,
    );
    decryptedFields.add(field);
    return ciphertext == null ? '' : String.fromCharCodes(ciphertext);
  }

  @override
  Uint8List? encryptNullable(
    String? plaintext, {
    required FieldCryptoContext context,
  }) {
    throw UnimplementedError();
  }
}

class _SecretRepository implements SecretRepository {
  _SecretRepository(this.item);

  final SecretItem item;
  final List<String> requestedIds = <String>[];

  @override
  Future<SecretItem?> getById(String id) async {
    requestedIds.add(id);
    return id == item.id ? item : null;
  }

  @override
  Future<List<SecretItem>> listByVault(String vaultId) async {
    return <SecretItem>[item];
  }

  @override
  Future<void> save(SecretItem item) async {}

  @override
  Future<void> softDelete(String id) async {}
}

class _NoteRepository implements NoteRepository {
  _NoteRepository(this.item);

  final NoteItem item;
  final List<String> requestedIds = <String>[];

  @override
  Future<NoteItem?> getById(String id) async {
    requestedIds.add(id);
    return id == item.id ? item : null;
  }

  @override
  Future<List<NoteItem>> listByVault(String vaultId) async {
    return <NoteItem>[item];
  }

  @override
  Future<void> save(NoteItem item) async {}

  @override
  Future<void> softDelete(String id) async {}
}
