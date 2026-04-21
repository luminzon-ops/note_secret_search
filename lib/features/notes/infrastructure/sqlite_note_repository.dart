import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteNoteRepository implements NoteRepository {
  SqliteNoteRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  @override
  Future<NoteItem?> getById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.noteItems,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapNote(rows.first, await _loadTags(db, id));
  }

  @override
  Future<List<NoteItem>> listByVault(String vaultId) async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.noteItems,
      where: 'vault_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[vaultId],
      orderBy: 'favorite DESC, updated_at DESC',
    );

    final items = <NoteItem>[];
    for (final row in rows) {
      final id = row['id']! as String;
      items.add(_mapNote(row, await _loadTags(db, id)));
    }
    return items;
  }

  @override
  Future<void> save(NoteItem item) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert(
        DatabaseSchema.noteItems,
        <String, Object?>{
          'id': item.id,
          'vault_id': item.vaultId,
          'title': item.title,
          'content_ciphertext': item.contentCiphertext,
          'summary_ciphertext': item.summaryCacheCiphertext,
          'category_id': item.categoryId,
          'favorite': item.favorite ? 1 : 0,
          'created_at': item.createdAt.millisecondsSinceEpoch,
          'updated_at': item.updatedAt.millisecondsSinceEpoch,
          'deleted_at': item.deletedAt?.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await _replaceTags(txn, item.id, item.vaultId, item.tags);
      await txn.delete(
        DatabaseSchema.embeddingChunks,
        where: 'source_id = ? AND source_type = ?',
        whereArgs: <Object>[item.id, SearchSourceType.note.name],
      );
    });
  }

  @override
  Future<void> softDelete(String id) async {
    final db = await _database.database;
    await db.update(
      DatabaseSchema.noteItems,
      <String, Object?>{'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
    await db.delete(
      DatabaseSchema.embeddingChunks,
      where: 'source_id = ? AND source_type = ?',
      whereArgs: <Object>[id, SearchSourceType.note.name],
    );
  }

  Future<List<String>> _loadTags(DatabaseExecutor db, String itemId) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.name
      FROM ${DatabaseSchema.tags} t
      INNER JOIN ${DatabaseSchema.itemTags} it ON it.tag_id = t.id
      WHERE it.item_id = ? AND it.item_type = ?
      ORDER BY t.name COLLATE NOCASE ASC
      ''',
      <Object>[itemId, 'note'],
    );

    return rows.map((row) => row['name']! as String).toList(growable: false);
  }

  Future<void> _replaceTags(
    DatabaseExecutor db,
    String itemId,
    String vaultId,
    List<String> tags,
  ) async {
    await db.delete(
      DatabaseSchema.itemTags,
      where: 'item_id = ? AND item_type = ?',
      whereArgs: <Object>[itemId, 'note'],
    );

    for (final tagName in tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty)) {
      final tagId = '$vaultId:$tagName';
      await db.insert(
        DatabaseSchema.tags,
        <String, Object?>{
          'id': tagId,
          'vault_id': vaultId,
          'name': tagName,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.insert(
        DatabaseSchema.itemTags,
        <String, Object?>{
          'item_id': itemId,
          'item_type': 'note',
          'tag_id': tagId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  NoteItem _mapNote(Map<String, Object?> row, List<String> tags) {
    return NoteItem(
      id: row['id']! as String,
      vaultId: row['vault_id']! as String,
      title: row['title']! as String,
      contentCiphertext: row['content_ciphertext']! as List<int>,
      summaryCacheCiphertext: row['summary_ciphertext'] as List<int>?,
      tags: tags,
      categoryId: row['category_id'] as String?,
      favorite: (row['favorite']! as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['deleted_at']! as int),
    );
  }
}
