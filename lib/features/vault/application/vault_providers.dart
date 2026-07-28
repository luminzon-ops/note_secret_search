import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/vault/domain/content_mutation_search_synchronizer.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';

final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  throw StateError(
    'vaultRepositoryProvider must be overridden by app composition',
  );
});

final contentMutationSearchSynchronizerProvider =
    Provider<ContentMutationSearchSynchronizer>((ref) {
      throw StateError(
        'contentMutationSearchSynchronizerProvider must be overridden by '
        'app composition',
      );
    });

final defaultVaultProvider = FutureProvider<Vault?>((ref) {
  return guardSensitiveFuture<Vault?>(
    ref,
    lockedValue: null,
    load: () => ref.watch(vaultRepositoryProvider).getDefaultVault(),
  );
});
