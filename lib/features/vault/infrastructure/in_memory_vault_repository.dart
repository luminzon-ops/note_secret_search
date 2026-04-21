import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';

class InMemoryVaultRepository implements VaultRepository {
  InMemoryVaultRepository()
      : _vaults = <String, Vault>{
          'default': Vault(
            id: 'default',
            name: '默认保险库',
            description: '首版默认保险库',
            isDefault: true,
            encryptionVersion: 1,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        };

  final Map<String, Vault> _vaults;

  @override
  Future<Vault?> getDefaultVault() async {
    return _vaults.values.where((vault) => vault.isDefault).firstOrNull;
  }

  @override
  Future<List<Vault>> listAll() async => _vaults.values.toList(growable: false);

  @override
  Future<void> save(Vault vault) async {
    _vaults[vault.id] = vault;
  }
}
