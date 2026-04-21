import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/secrets/domain/secret_draft.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:uuid/uuid.dart';

abstract final class SecretFormMapper {
  static const _uuid = Uuid();

  static SecretItem create({
    required String vaultId,
    required SecretDraft draft,
    required CryptoService cryptoService,
  }) {
    final now = DateTime.now();
    return SecretItem(
      id: _uuid.v4(),
      vaultId: vaultId,
      title: draft.title.trim(),
      usernameCiphertext: cryptoService.encryptNullable(draft.username),
      passwordCiphertext: cryptoService.encryptNullable(draft.password),
      websiteUrlCiphertext: cryptoService.encryptNullable(draft.websiteUrl),
      noteCiphertext: cryptoService.encryptNullable(draft.note),
      tags: draft.tags,
      categoryId: draft.categoryId,
      favorite: draft.favorite,
      createdAt: now,
      updatedAt: now,
      lastAccessedAt: null,
      deletedAt: null,
    );
  }

  static SecretItem update({
    required SecretItem previous,
    required SecretDraft draft,
    required CryptoService cryptoService,
  }) {
    return SecretItem(
      id: previous.id,
      vaultId: previous.vaultId,
      title: draft.title.trim(),
      usernameCiphertext: cryptoService.encryptNullable(draft.username),
      passwordCiphertext: cryptoService.encryptNullable(draft.password),
      websiteUrlCiphertext: cryptoService.encryptNullable(draft.websiteUrl),
      noteCiphertext: cryptoService.encryptNullable(draft.note),
      tags: draft.tags,
      categoryId: draft.categoryId,
      favorite: draft.favorite,
      createdAt: previous.createdAt,
      updatedAt: DateTime.now(),
      lastAccessedAt: previous.lastAccessedAt,
      deletedAt: previous.deletedAt,
    );
  }

  static SecretDraft toDraft(SecretItem item, CryptoService cryptoService) {
    return SecretDraft(
      title: item.title,
      username: cryptoService.decryptNullable(item.usernameCiphertext),
      password: cryptoService.decryptNullable(item.passwordCiphertext),
      websiteUrl: cryptoService.decryptNullable(item.websiteUrlCiphertext),
      note: cryptoService.decryptNullable(item.noteCiphertext),
      tags: item.tags,
      categoryId: item.categoryId,
      favorite: item.favorite,
    );
  }
}
