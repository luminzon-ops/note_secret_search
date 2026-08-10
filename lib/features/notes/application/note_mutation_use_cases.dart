import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/features/notes/application/note_form_mapper.dart';
import 'package:note_secret_search/features/notes/domain/note_draft.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/vault/domain/content_mutation_search_synchronizer.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';

typedef NoteProjectionRefresher = void Function(String noteId);

class SaveNoteUseCase {
  const SaveNoteUseCase({
    required NoteRepository repository,
    required VaultRepository vaultRepository,
    required CryptoService cryptoService,
    required ContentMutationSearchSynchronizer searchSynchronizer,
    required NoteProjectionRefresher refreshProjections,
  }) : _repository = repository,
       _vaultRepository = vaultRepository,
       _cryptoService = cryptoService,
       _searchSynchronizer = searchSynchronizer,
       _refreshProjections = refreshProjections;

  final NoteRepository _repository;
  final VaultRepository _vaultRepository;
  final CryptoService _cryptoService;
  final ContentMutationSearchSynchronizer _searchSynchronizer;
  final NoteProjectionRefresher _refreshProjections;

  Future<NoteItem?> execute({
    required NoteItem? existing,
    required NoteDraft draft,
  }) async {
    final vault = await _vaultRepository.getDefaultVault();
    if (vault == null) {
      return null;
    }

    final item = existing == null
        ? NoteFormMapper.create(
            vaultId: vault.id,
            draft: draft,
            cryptoService: _cryptoService,
          )
        : NoteFormMapper.update(
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

class DeleteNoteUseCase {
  const DeleteNoteUseCase({
    required NoteRepository repository,
    required ContentMutationSearchSynchronizer searchSynchronizer,
    required NoteProjectionRefresher refreshProjections,
  }) : _repository = repository,
       _searchSynchronizer = searchSynchronizer,
       _refreshProjections = refreshProjections;

  final NoteRepository _repository;
  final ContentMutationSearchSynchronizer _searchSynchronizer;
  final NoteProjectionRefresher _refreshProjections;

  Future<void> execute(String noteId) async {
    await _repository.softDelete(noteId);
    _refreshProjections(noteId);
    await _searchSynchronizer.synchronize();
  }
}
