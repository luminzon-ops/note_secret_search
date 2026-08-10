import 'package:note_secret_search/core/storage/database/sqlite_item_tag_store.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

class RecordingItemTagStore implements ItemTagStore {
  RecordingItemTagStore({
    Map<String, List<String>> tagsByItemId = const <String, List<String>>{},
  }) : _tagsByItemId = tagsByItemId;

  final Map<String, List<String>> _tagsByItemId;
  int loadCallCount = 0;
  List<String>? lastItemIds;
  ItemTagType? lastItemType;
  String? lastVaultId;

  @override
  Future<Map<String, List<String>>> loadTagsByItemIds(
    DatabaseExecutor executor, {
    required List<String> itemIds,
    required ItemTagType itemType,
    required String vaultId,
  }) async {
    loadCallCount += 1;
    lastItemIds = List<String>.of(itemIds);
    lastItemType = itemType;
    lastVaultId = vaultId;
    return <String, List<String>>{
      for (final itemId in itemIds)
        itemId: List<String>.of(_tagsByItemId[itemId] ?? const <String>[]),
    };
  }

  @override
  Future<void> replaceTags(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
    required List<String> tags,
  }) {
    throw StateError('unexpected_tag_write');
  }

  @override
  Future<void> unlinkItem(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
  }) {
    throw StateError('unexpected_tag_unlink');
  }
}
