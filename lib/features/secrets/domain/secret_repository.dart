import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';

abstract interface class SecretRepository {
  Future<List<SecretItem>> listByVault(String vaultId);

  Future<SecretItem?> getById(String id);

  Future<void> save(SecretItem item);

  Future<void> softDelete(String id);

  Future<Vault?> getDefaultVault();
}
