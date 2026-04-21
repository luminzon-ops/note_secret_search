import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/secrets/application/secret_providers.dart';

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return SqliteNoteRepository(database: ref.watch(appDatabaseProvider));
});

final noteListProvider = FutureProvider<List<NoteItem>>((ref) async {
  final vault = await ref.watch(defaultVaultProvider.future);
  if (vault == null) {
    return const <NoteItem>[];
  }

  return ref.watch(noteRepositoryProvider).listByVault(vault.id);
});

final noteDetailProvider = FutureProvider.family<NoteItem?, String>((ref, id) async {
  return ref.watch(noteRepositoryProvider).getById(id);
});
