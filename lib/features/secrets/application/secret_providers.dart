import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/secrets/application/secret_mutation_use_cases.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';

final secretRepositoryProvider = Provider<SecretRepository>((ref) {
  throw StateError(
    'secretRepositoryProvider must be overridden by app composition',
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

final secretDetailProvider = FutureProvider.family<SecretItem?, String>((
  ref,
  id,
) {
  return guardSensitiveFuture<SecretItem?>(
    ref,
    lockedValue: null,
    load: () => ref.watch(secretRepositoryProvider).getById(id),
  );
});

final saveSecretUseCaseProvider = Provider<SaveSecretUseCase>((ref) {
  return SaveSecretUseCase(
    repository: ref.watch(secretRepositoryProvider),
    vaultRepository: ref.watch(vaultRepositoryProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
    searchSynchronizer: ref.watch(contentMutationSearchSynchronizerProvider),
    refreshProjections: (secretId) {
      ref.invalidate(secretListProvider);
      ref.invalidate(secretDetailProvider(secretId));
    },
  );
});

final deleteSecretUseCaseProvider = Provider<DeleteSecretUseCase>((ref) {
  return DeleteSecretUseCase(
    repository: ref.watch(secretRepositoryProvider),
    searchSynchronizer: ref.watch(contentMutationSearchSynchronizerProvider),
    refreshProjections: (secretId) {
      ref.invalidate(secretListProvider);
      ref.invalidate(secretDetailProvider(secretId));
    },
  );
});
