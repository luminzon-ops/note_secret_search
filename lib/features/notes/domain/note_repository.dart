import 'package:note_secret_search/features/notes/domain/note_item.dart';

abstract interface class NoteRepository {
  Future<List<NoteItem>> listByVault(String vaultId);

  Future<NoteItem?> getById(String id);

  Future<void> save(NoteItem item);

  Future<void> softDelete(String id);
}
