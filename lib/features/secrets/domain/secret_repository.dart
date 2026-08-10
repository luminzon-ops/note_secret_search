import 'package:note_secret_search/features/secrets/domain/secret_item.dart';

abstract interface class SecretRepository {
  Future<List<SecretItem>> listByVault(String vaultId);

  Future<SecretItem?> getById(String id);

  Future<void> save(SecretItem item);

  Future<void> softDelete(String id);
}

abstract interface class SecretSearchReader {
  Future<List<SecretItem>> listByVaultPage(
    String vaultId, {
    String? afterId,
    int limit = 128,
  });

  Future<List<SecretItem>> listByVaultIds(String vaultId, Iterable<String> ids);
}
