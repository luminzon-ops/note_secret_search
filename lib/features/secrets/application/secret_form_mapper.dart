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
    final id = _uuid.v4();
    return SecretItem(
      id: id,
      vaultId: vaultId,
      title: draft.title.trim(),
      usernameCiphertext: cryptoService.encryptField(
        draft.username,
        field: EncryptedDatabaseField.secretUsername,
        rowId: id,
      ),
      passwordCiphertext: cryptoService.encryptField(
        draft.password,
        field: EncryptedDatabaseField.secretPassword,
        rowId: id,
      ),
      websiteUrlCiphertext: cryptoService.encryptField(
        draft.websiteUrl,
        field: EncryptedDatabaseField.secretWebsiteUrl,
        rowId: id,
      ),
      noteCiphertext: cryptoService.encryptField(
        draft.note,
        field: EncryptedDatabaseField.secretNote,
        rowId: id,
      ),
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
      usernameCiphertext: _updatedCiphertext(
        previousCiphertext: previous.usernameCiphertext,
        plaintext: draft.username,
        field: EncryptedDatabaseField.secretUsername,
        rowId: previous.id,
        cryptoService: cryptoService,
      ),
      passwordCiphertext: _updatedCiphertext(
        previousCiphertext: previous.passwordCiphertext,
        plaintext: draft.password,
        field: EncryptedDatabaseField.secretPassword,
        rowId: previous.id,
        cryptoService: cryptoService,
      ),
      websiteUrlCiphertext: _updatedCiphertext(
        previousCiphertext: previous.websiteUrlCiphertext,
        plaintext: draft.websiteUrl,
        field: EncryptedDatabaseField.secretWebsiteUrl,
        rowId: previous.id,
        cryptoService: cryptoService,
      ),
      noteCiphertext: _updatedCiphertext(
        previousCiphertext: previous.noteCiphertext,
        plaintext: draft.note,
        field: EncryptedDatabaseField.secretNote,
        rowId: previous.id,
        cryptoService: cryptoService,
      ),
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
      username: cryptoService.decryptField(
        item.usernameCiphertext,
        field: EncryptedDatabaseField.secretUsername,
        rowId: item.id,
      ),
      password: cryptoService.decryptField(
        item.passwordCiphertext,
        field: EncryptedDatabaseField.secretPassword,
        rowId: item.id,
      ),
      websiteUrl: cryptoService.decryptField(
        item.websiteUrlCiphertext,
        field: EncryptedDatabaseField.secretWebsiteUrl,
        rowId: item.id,
      ),
      note: cryptoService.decryptField(
        item.noteCiphertext,
        field: EncryptedDatabaseField.secretNote,
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
