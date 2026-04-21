import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';

class InMemorySecretRepository implements SecretRepository {
  final Map<String, SecretItem> _items = <String, SecretItem>{};

  @override
  Future<Vault?> getDefaultVault() async => null;

  @override
  Future<SecretItem?> getById(String id) async => _items[id];

  @override
  Future<List<SecretItem>> listByVault(String vaultId) async {
    return _items.values.where((item) => item.vaultId == vaultId).toList(growable: false);
  }

  @override
  Future<void> save(SecretItem item) async {
    _items[item.id] = item;
  }

  @override
  Future<void> softDelete(String id) async {
    _items.remove(id);
  }
}
