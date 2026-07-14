import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';
import 'package:note_secret_search/features/vault/infrastructure/sqlite_vault_repository.dart';

final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  return SqliteVaultRepository(database: ref.watch(appDatabaseProvider));
});

final secretRepositoryProvider = Provider<SecretRepository>((ref) {
  return SqliteSecretRepository(
    database: ref.watch(appDatabaseProvider),
    vaultRepository: ref.watch(vaultRepositoryProvider),
  );
});

final defaultVaultProvider = FutureProvider<Vault?>((ref) {
  return guardSensitiveFuture<Vault?>(
    ref,
    lockedValue: null,
    load: () => ref.watch(vaultRepositoryProvider).getDefaultVault(),
  );
});

final secretListProvider = FutureProvider<List<SecretItem>>((ref) {
  return guardSensitiveFuture<List<SecretItem>>(
    ref,
    lockedValue: const <SecretItem>[],
    load: () async {
      final vault = await ref.watch(defaultVaultProvider.future);
      if (vault == null) {
        return const <SecretItem>[];
      }

      return ref.watch(secretRepositoryProvider).listByVault(vault.id);
    },
  );
});

final secretDetailProvider =
    FutureProvider.family<SecretItem?, String>((ref, id) {
  return guardSensitiveFuture<SecretItem?>(
    ref,
    lockedValue: null,
    load: () => ref.watch(secretRepositoryProvider).getById(id),
  );
});
