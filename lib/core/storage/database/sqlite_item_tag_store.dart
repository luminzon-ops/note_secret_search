import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';
import 'package:uuid/uuid.dart';

enum ItemTagType { secret, note }

abstract interface class ItemTagStore {
  Future<Map<String, List<String>>> loadTagsByItemIds(
    DatabaseExecutor executor, {
    required List<String> itemIds,
    required ItemTagType itemType,
    required String vaultId,
  });

  Future<void> replaceTags(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
    required List<String> tags,
  });

  Future<void> unlinkItem(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
  });
}

class SqliteItemTagStore implements ItemTagStore {
  SqliteItemTagStore({
    String Function()? idFactory,
    int Function()? nowMilliseconds,
  }) : _idFactory = idFactory ?? _newTagId,
       _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String Function() _idFactory;
  final int Function() _nowMilliseconds;

  @override
  Future<Map<String, List<String>>> loadTagsByItemIds(
    DatabaseExecutor executor, {
    required List<String> itemIds,
    required ItemTagType itemType,
    required String vaultId,
  }) async {
    final tagsByItemId = <String, List<String>>{
      for (final itemId in itemIds) itemId: <String>[],
    };
    if (tagsByItemId.isEmpty) {
      return tagsByItemId;
    }
    final placeholders = List<String>.filled(
      tagsByItemId.length,
      '?',
      growable: false,
    ).join(', ');
    final rows = await executor.rawQuery(
      '''
      SELECT link.item_id, tag.name
      FROM ${DatabaseSchema.itemTags} link
      INNER JOIN ${DatabaseSchema.tags} tag ON tag.id = link.tag_id
      WHERE link.item_type = ?
        AND tag.vault_id = ?
        AND link.item_id IN ($placeholders)
      ORDER BY link.item_id ASC, tag.name COLLATE NOCASE ASC, tag.id ASC
      ''',
      <Object>[itemType.name, vaultId, ...tagsByItemId.keys],
    );
    for (final row in rows) {
      tagsByItemId[row['item_id']! as String]!.add(row['name']! as String);
    }
    return tagsByItemId;
  }

  @override
  Future<void> replaceTags(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
    required List<String> tags,
  }) async {
    final normalizedNames = _normalizeTagNames(tags);
    final existingRows = await executor.query(
      DatabaseSchema.tags,
      columns: const <String>['id', 'name'],
      where: 'vault_id = ?',
      whereArgs: <Object>[vaultId],
      orderBy: 'created_at ASC, id ASC',
    );
    final tagsByName = <String, String>{
      for (final row in existingRows)
        _sqliteNoCaseKey(row['name']! as String): row['id']! as String,
    };

    await executor.delete(
      DatabaseSchema.itemTags,
      where: 'item_id = ? AND item_type = ?',
      whereArgs: <Object>[itemId, itemType.name],
    );
    for (final entry in normalizedNames.entries) {
      var tagId = tagsByName[entry.key];
      if (tagId == null) {
        tagId = _idFactory();
        await executor.insert(DatabaseSchema.tags, <String, Object?>{
          'id': tagId,
          'vault_id': vaultId,
          'name': entry.value,
          'created_at': _nowMilliseconds(),
        });
        tagsByName[entry.key] = tagId;
      }
      await executor.rawInsert(
        '''
        INSERT OR IGNORE INTO ${DatabaseSchema.itemTags} (
          item_id,
          item_type,
          tag_id
        ) VALUES (?, ?, ?)
        ''',
        <Object>[itemId, itemType.name, tagId],
      );
    }
    await _deleteOrphanTags(executor, vaultId);
  }

  @override
  Future<void> unlinkItem(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
  }) async {
    await executor.delete(
      DatabaseSchema.itemTags,
      where: 'item_id = ? AND item_type = ?',
      whereArgs: <Object>[itemId, itemType.name],
    );
    await _deleteOrphanTags(executor, vaultId);
  }

  Future<void> _deleteOrphanTags(DatabaseExecutor executor, String vaultId) {
    return executor.rawDelete(
      '''
      DELETE FROM ${DatabaseSchema.tags}
      WHERE vault_id = ?
        AND NOT EXISTS (
          SELECT 1
          FROM ${DatabaseSchema.itemTags}
          WHERE ${DatabaseSchema.itemTags}.tag_id = ${DatabaseSchema.tags}.id
        )
      ''',
      <Object>[vaultId],
    );
  }
}

Map<String, String> _normalizeTagNames(List<String> tags) {
  final normalized = <String, String>{};
  for (final rawName in tags) {
    final name = rawName.trim();
    if (name.isEmpty) {
      continue;
    }
    normalized.putIfAbsent(_sqliteNoCaseKey(name), () => name);
  }
  return normalized;
}

String _sqliteNoCaseKey(String value) {
  final buffer = StringBuffer();
  for (final codePoint in value.runes) {
    buffer.writeCharCode(
      codePoint >= 0x41 && codePoint <= 0x5a ? codePoint + 0x20 : codePoint,
    );
  }
  return buffer.toString();
}

String _newTagId() => const Uuid().v4();
