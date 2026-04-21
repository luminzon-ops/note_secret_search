import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteVaultRepository implements VaultRepository {
  SqliteVaultRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  @override
  Future<Vault?> getDefaultVault() async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.vaults,
      where: 'is_default = ?',
      whereArgs: const <Object>[1],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapVault(rows.first);
  }

  @override
  Future<List<Vault>> listAll() async {
    final db = await _database.database;
    final rows = await db.query(DatabaseSchema.vaults, orderBy: 'created_at ASC');
    return rows.map(_mapVault).toList(growable: false);
  }

  @override
  Future<void> save(Vault vault) async {
    final db = await _database.database;
    await db.insert(
      DatabaseSchema.vaults,
      <String, Object?>{
        'id': vault.id,
        'name': vault.name,
        'description': vault.description,
        'is_default': vault.isDefault ? 1 : 0,
        'encryption_version': vault.encryptionVersion,
        'created_at': vault.createdAt.millisecondsSinceEpoch,
        'updated_at': vault.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Vault _mapVault(Map<String, Object?> row) {
    return Vault(
      id: row['id']! as String,
      name: row['name']! as String,
      description: row['description'] as String?,
      isDefault: (row['is_default']! as int) == 1,
      encryptionVersion: row['encryption_version']! as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    );
  }
}
