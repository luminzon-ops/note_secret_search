import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/core_security_providers.dart';
import 'package:note_secret_search/features/notes/application/note_mutation_use_cases.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/vault/application/vault_providers.dart';

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  throw StateError(
    'noteRepositoryProvider must be overridden by app composition',
  );
});

final noteListProvider = FutureProvider<List<NoteItem>>((ref) {
  return guardSensitiveFuture<List<NoteItem>>(
    ref,
    lockedValue: const <NoteItem>[],
    load: () async {
      final vault = await ref.watch(defaultVaultProvider.future);
      if (vault == null) {
        return const <NoteItem>[];
      }

      return ref.watch(noteRepositoryProvider).listByVault(vault.id);
    },
  );
});

final noteDetailProvider = FutureProvider.family<NoteItem?, String>((ref, id) {
  return guardSensitiveFuture<NoteItem?>(
    ref,
    lockedValue: null,
    load: () => ref.watch(noteRepositoryProvider).getById(id),
  );
});

final saveNoteUseCaseProvider = Provider<SaveNoteUseCase>((ref) {
  return SaveNoteUseCase(
    repository: ref.watch(noteRepositoryProvider),
    vaultRepository: ref.watch(vaultRepositoryProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
    searchSynchronizer: ref.watch(contentMutationSearchSynchronizerProvider),
    refreshProjections: (noteId) {
      ref.invalidate(noteListProvider);
      ref.invalidate(noteDetailProvider(noteId));
    },
  );
});

final deleteNoteUseCaseProvider = Provider<DeleteNoteUseCase>((ref) {
  return DeleteNoteUseCase(
    repository: ref.watch(noteRepositoryProvider),
    searchSynchronizer: ref.watch(contentMutationSearchSynchronizerProvider),
    refreshProjections: (noteId) {
      ref.invalidate(noteListProvider);
      ref.invalidate(noteDetailProvider(noteId));
    },
  );
});
