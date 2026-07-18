import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';
import 'package:note_secret_search/features/vault/infrastructure/sqlite_vault_repository.dart';

final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  return SqliteVaultRepository(database: ref.watch(appDatabaseProvider));
});

final defaultVaultProvider = FutureProvider<Vault?>((ref) {
  return guardSensitiveFuture<Vault?>(
    ref,
    lockedValue: null,
    load: () => ref.watch(vaultRepositoryProvider).getDefaultVault(),
  );
});
