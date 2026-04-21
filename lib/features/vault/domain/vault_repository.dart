import 'package:note_secret_search/features/vault/domain/vault.dart';

abstract interface class VaultRepository {
  Future<Vault?> getDefaultVault();

  Future<List<Vault>> listAll();

  Future<void> save(Vault vault);
}
