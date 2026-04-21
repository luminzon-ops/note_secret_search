import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';

class InMemoryNoteRepository implements NoteRepository {
  final Map<String, NoteItem> _items = <String, NoteItem>{};

  @override
  Future<NoteItem?> getById(String id) async => _items[id];

  @override
  Future<List<NoteItem>> listByVault(String vaultId) async {
    return _items.values.where((item) => item.vaultId == vaultId).toList(growable: false);
  }

  @override
  Future<void> save(NoteItem item) async {
    _items[item.id] = item;
  }

  @override
  Future<void> softDelete(String id) async {
    _items.remove(id);
  }
}
