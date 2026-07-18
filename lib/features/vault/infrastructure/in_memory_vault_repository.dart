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
    final existing = _vaults[vault.id];
    if (!vault.isDefault && existing?.isDefault == true) {
      throw StateError('vault_default_required');
    }
    final updated = <String, Vault>{..._vaults};
    if (vault.isDefault) {
      for (final entry in updated.entries.toList(growable: false)) {
        if (entry.key != vault.id && entry.value.isDefault) {
          updated[entry.key] = _withDefault(entry.value, false);
        }
      }
    }
    updated[vault.id] = vault;
    if (updated.values.where((entry) => entry.isDefault).length != 1) {
      throw StateError('vault_default_required');
    }
    _vaults
      ..clear()
      ..addAll(updated);
  }
}

Vault _withDefault(Vault vault, bool isDefault) {
  return Vault(
    id: vault.id,
    name: vault.name,
    description: vault.description,
    isDefault: isDefault,
    encryptionVersion: vault.encryptionVersion,
    createdAt: vault.createdAt,
    updatedAt: vault.updatedAt,
  );
}
