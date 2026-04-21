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
    return NoteItem(
      id: _uuid.v4(),
      vaultId: vaultId,
      title: draft.title.trim(),
      contentCiphertext: cryptoService.encryptNullable(draft.content) ?? <int>[],
      summaryCacheCiphertext: cryptoService.encryptNullable(draft.summary),
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
      contentCiphertext: cryptoService.encryptNullable(draft.content) ?? <int>[],
      summaryCacheCiphertext: cryptoService.encryptNullable(draft.summary),
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
      content: cryptoService.decryptNullable(item.contentCiphertext),
      summary: cryptoService.decryptNullable(item.summaryCacheCiphertext),
      tags: item.tags,
      categoryId: item.categoryId,
      favorite: item.favorite,
    );
  }
}
