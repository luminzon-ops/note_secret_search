import 'package:note_secret_search/features/notes/domain/note_item.dart';

abstract interface class NoteRepository {
  Future<List<NoteItem>> listByVault(String vaultId);

  Future<NoteItem?> getById(String id);

  Future<void> save(NoteItem item);

  Future<void> softDelete(String id);
}

abstract interface class NoteSearchReader {
  Future<List<NoteItem>> listByVaultPage(
    String vaultId, {
    String? afterId,
    int limit = 128,
  });

  Future<List<NoteItem>> listByVaultIds(String vaultId, Iterable<String> ids);
}
