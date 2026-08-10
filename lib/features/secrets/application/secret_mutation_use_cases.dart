import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/secrets/application/secret_form_mapper.dart';
import 'package:note_secret_search/features/secrets/domain/secret_draft.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/vault/domain/content_mutation_search_synchronizer.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';

typedef SecretProjectionRefresher = void Function(String secretId);

class SaveSecretUseCase {
  const SaveSecretUseCase({
    required SecretRepository repository,
    required VaultRepository vaultRepository,
    required CryptoService cryptoService,
    required ContentMutationSearchSynchronizer searchSynchronizer,
    required SecretProjectionRefresher refreshProjections,
  }) : _repository = repository,
       _vaultRepository = vaultRepository,
       _cryptoService = cryptoService,
       _searchSynchronizer = searchSynchronizer,
       _refreshProjections = refreshProjections;

  final SecretRepository _repository;
  final VaultRepository _vaultRepository;
  final CryptoService _cryptoService;
  final ContentMutationSearchSynchronizer _searchSynchronizer;
  final SecretProjectionRefresher _refreshProjections;

  Future<SecretItem?> execute({
    required SecretItem? existing,
    required SecretDraft draft,
  }) async {
    final vault = await _vaultRepository.getDefaultVault();
    if (vault == null) {
      return null;
    }

    final item = existing == null
        ? SecretFormMapper.create(
            vaultId: vault.id,
            draft: draft,
            cryptoService: _cryptoService,
          )
        : SecretFormMapper.update(
            previous: existing,
            draft: draft,
            cryptoService: _cryptoService,
          );

    await _repository.save(item);
    _refreshProjections(item.id);
    await _searchSynchronizer.synchronize();
    return item;
  }
}

class DeleteSecretUseCase {
  const DeleteSecretUseCase({
    required SecretRepository repository,
    required ContentMutationSearchSynchronizer searchSynchronizer,
    required SecretProjectionRefresher refreshProjections,
  }) : _repository = repository,
       _searchSynchronizer = searchSynchronizer,
       _refreshProjections = refreshProjections;

  final SecretRepository _repository;
  final ContentMutationSearchSynchronizer _searchSynchronizer;
  final SecretProjectionRefresher _refreshProjections;

  Future<void> execute(String secretId) async {
    await _repository.softDelete(secretId);
    _refreshProjections(secretId);
    await _searchSynchronizer.synchronize();
  }
}
