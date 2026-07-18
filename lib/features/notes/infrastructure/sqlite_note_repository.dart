import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_item_tag_store.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/domain/note_repository.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteNoteRepository implements NoteRepository {
  SqliteNoteRepository({
    required AppDatabase database,
    ItemTagStore? tagStore,
    int Function()? nowMilliseconds,
  }) : _database = database,
       _tagStore = tagStore ?? SqliteItemTagStore(),
       _nowMilliseconds =
           nowMilliseconds ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _database;
  final ItemTagStore _tagStore;
  final int Function() _nowMilliseconds;

  @override
  Future<NoteItem?> getById(String id) {
    return _database.run((db) async {
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
    });
  }

  @override
  Future<List<NoteItem>> listByVault(String vaultId) {
    return _database.run((db) async {
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
    });
  }

  @override
  Future<void> save(NoteItem item) async {
    _validateCiphertexts(item);
    await _database.transaction((executor) async {
      await executor.rawInsert(
        '''
        INSERT INTO ${DatabaseSchema.noteItems} (
          id,
          vault_id,
          title,
          content_ciphertext,
          summary_ciphertext,
          category_id,
          favorite,
          created_at,
          updated_at,
          deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          vault_id = excluded.vault_id,
          title = excluded.title,
          content_ciphertext = excluded.content_ciphertext,
          summary_ciphertext = excluded.summary_ciphertext,
          category_id = excluded.category_id,
          favorite = excluded.favorite,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          deleted_at = excluded.deleted_at
        ''',
        <Object?>[
          item.id,
          item.vaultId,
          item.title,
          item.contentCiphertext,
          item.summaryCacheCiphertext,
          item.categoryId,
          item.favorite ? 1 : 0,
          item.createdAt.millisecondsSinceEpoch,
          item.updatedAt.millisecondsSinceEpoch,
          item.deletedAt?.millisecondsSinceEpoch,
        ],
      );
      await _tagStore.replaceTags(
        executor,
        itemId: item.id,
        itemType: ItemTagType.note,
        vaultId: item.vaultId,
        tags: item.tags,
      );
      await executor.delete(
        DatabaseSchema.embeddingChunks,
        where: 'source_id = ? AND source_type = ?',
        whereArgs: <Object>[item.id, SearchSourceType.note.name],
      );
    });
  }

  @override
  Future<void> softDelete(String id) {
    return _database.transaction((executor) async {
      final rows = await executor.query(
        DatabaseSchema.noteItems,
        columns: const <String>['vault_id', 'deleted_at'],
        where: 'id = ?',
        whereArgs: <Object>[id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }
      final vaultId = rows.single['vault_id']! as String;
      if (rows.single['deleted_at'] == null) {
        await executor.update(
          DatabaseSchema.noteItems,
          <String, Object?>{'deleted_at': _nowMilliseconds()},
          where: 'id = ?',
          whereArgs: <Object>[id],
        );
      }
      await _tagStore.unlinkItem(
        executor,
        itemId: id,
        itemType: ItemTagType.note,
        vaultId: vaultId,
      );
      await executor.delete(
        DatabaseSchema.embeddingChunks,
        where: 'source_id = ? AND source_type = ?',
        whereArgs: <Object>[id, SearchSourceType.note.name],
      );
    });
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

  NoteItem _mapNote(Map<String, Object?> row, List<String> tags) {
    return NoteItem(
      id: row['id']! as String,
      vaultId: row['vault_id']! as String,
      title: row['title']! as String,
      contentCiphertext: _requireNssf(row['content_ciphertext']! as List<int>),
      summaryCacheCiphertext: _requireOptionalNssf(
        row['summary_ciphertext'] as List<int>?,
      ),
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

  void _validateCiphertexts(NoteItem item) {
    _requireNssf(item.contentCiphertext);
    _requireOptionalNssf(item.summaryCacheCiphertext);
  }

  List<int> _requireNssf(List<int> ciphertext) {
    FieldEnvelopeCodec.decode(ciphertext);
    return ciphertext;
  }

  List<int>? _requireOptionalNssf(List<int>? ciphertext) {
    if (ciphertext != null) {
      _requireNssf(ciphertext);
    }
    return ciphertext;
  }
}
