import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/domain/note_draft.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:uuid/uuid.dart';

abstract final class NoteFormMapper {
  static const _uuid = Uuid();

  static NoteItem create({
    required String vaultId,
    required NoteDraft draft,
    required CryptoService cryptoService,
  }) {
    final now = DateTime.now();
    final id = _uuid.v4();
    return NoteItem(
      id: id,
      vaultId: vaultId,
      title: draft.title.trim(),
      contentCiphertext:
          cryptoService.encryptField(
            draft.content,
            field: EncryptedDatabaseField.noteContent,
            rowId: id,
          ) ??
          <int>[],
      summaryCacheCiphertext: cryptoService.encryptField(
        draft.summary,
        field: EncryptedDatabaseField.noteSummary,
        rowId: id,
      ),
      tags: draft.tags,
      categoryId: draft.categoryId,
      favorite: draft.favorite,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
  }

  static NoteItem update({
    required NoteItem previous,
    required NoteDraft draft,
    required CryptoService cryptoService,
  }) {
    return NoteItem(
      id: previous.id,
      vaultId: previous.vaultId,
      title: draft.title.trim(),
      contentCiphertext:
          _updatedCiphertext(
            previousCiphertext: previous.contentCiphertext,
            plaintext: draft.content,
            field: EncryptedDatabaseField.noteContent,
            rowId: previous.id,
            cryptoService: cryptoService,
          ) ??
          <int>[],
      summaryCacheCiphertext: _updatedCiphertext(
        previousCiphertext: previous.summaryCacheCiphertext,
        plaintext: draft.summary,
        field: EncryptedDatabaseField.noteSummary,
        rowId: previous.id,
        cryptoService: cryptoService,
      ),
      tags: draft.tags,
      categoryId: draft.categoryId,
      favorite: draft.favorite,
      createdAt: previous.createdAt,
      updatedAt: DateTime.now(),
      deletedAt: previous.deletedAt,
    );
  }

  static NoteDraft toDraft(NoteItem item, CryptoService cryptoService) {
    return NoteDraft(
      title: item.title,
      content: cryptoService.decryptField(
        item.contentCiphertext,
        field: EncryptedDatabaseField.noteContent,
        rowId: item.id,
      ),
      summary: cryptoService.decryptField(
        item.summaryCacheCiphertext,
        field: EncryptedDatabaseField.noteSummary,
        rowId: item.id,
      ),
      tags: item.tags,
      categoryId: item.categoryId,
      favorite: item.favorite,
    );
  }

  static List<int>? _updatedCiphertext({
    required List<int>? previousCiphertext,
    required String plaintext,
    required EncryptedDatabaseField field,
    required String rowId,
    required CryptoService cryptoService,
  }) {
    final previousPlaintext = cryptoService.decryptField(
      previousCiphertext,
      field: field,
      rowId: rowId,
    );
    return previousPlaintext == plaintext
        ? previousCiphertext
        : cryptoService.encryptField(plaintext, field: field, rowId: rowId);
  }
}
