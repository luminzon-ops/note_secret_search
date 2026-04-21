import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/search/domain/embedding_chunk.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/domain/secret_repository.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteSecretRepository implements SecretRepository {
  SqliteSecretRepository({
    required AppDatabase database,
    required VaultRepository vaultRepository,
  })  : _database = database,
        _vaultRepository = vaultRepository;

  final AppDatabase _database;
  final VaultRepository _vaultRepository;

  @override
  Future<Vault?> getDefaultVault() {
    return _vaultRepository.getDefaultVault();
  }

  @override
  Future<SecretItem?> getById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.secretItems,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapSecret(rows.first, await _loadTags(db, id));
  }

  @override
  Future<List<SecretItem>> listByVault(String vaultId) async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.secretItems,
      where: 'vault_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[vaultId],
      orderBy: 'favorite DESC, updated_at DESC',
    );

    final items = <SecretItem>[];
    for (final row in rows) {
      final id = row['id']! as String;
      items.add(_mapSecret(row, await _loadTags(db, id)));
    }
    return items;
  }

  @override
  Future<void> save(SecretItem item) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert(
        DatabaseSchema.secretItems,
        <String, Object?>{
          'id': item.id,
          'vault_id': item.vaultId,
          'title': item.title,
          'username_ciphertext': item.usernameCiphertext,
          'password_ciphertext': item.passwordCiphertext,
          'website_url_ciphertext': item.websiteUrlCiphertext,
          'note_ciphertext': item.noteCiphertext,
          'category_id': item.categoryId,
          'favorite': item.favorite ? 1 : 0,
          'created_at': item.createdAt.millisecondsSinceEpoch,
          'updated_at': item.updatedAt.millisecondsSinceEpoch,
          'last_accessed_at': item.lastAccessedAt?.millisecondsSinceEpoch,
          'deleted_at': item.deletedAt?.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await _replaceTags(txn, item.id, item.vaultId, item.tags);
      await txn.delete(
        DatabaseSchema.embeddingChunks,
        where: 'source_id = ? AND source_type = ?',
        whereArgs: <Object>[item.id, SearchSourceType.secret.name],
      );
    });
  }

  @override
  Future<void> softDelete(String id) async {
    final db = await _database.database;
    await db.update(
      DatabaseSchema.secretItems,
      <String, Object?>{'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
    await db.delete(
      DatabaseSchema.embeddingChunks,
      where: 'source_id = ? AND source_type = ?',
      whereArgs: <Object>[id, SearchSourceType.secret.name],
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
      <Object>[itemId, 'secret'],
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
      whereArgs: <Object>[itemId, 'secret'],
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
          'item_type': 'secret',
          'tag_id': tagId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  SecretItem _mapSecret(Map<String, Object?> row, List<String> tags) {
    return SecretItem(
      id: row['id']! as String,
      vaultId: row['vault_id']! as String,
      title: row['title']! as String,
      usernameCiphertext: row['username_ciphertext'] as List<int>?,
      passwordCiphertext: row['password_ciphertext'] as List<int>?,
      websiteUrlCiphertext: row['website_url_ciphertext'] as List<int>?,
      noteCiphertext: row['note_ciphertext'] as List<int>?,
      tags: tags,
      categoryId: row['category_id'] as String?,
      favorite: (row['favorite']! as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      lastAccessedAt: row['last_accessed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['last_accessed_at']! as int),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['deleted_at']! as int),
    );
  }
}
