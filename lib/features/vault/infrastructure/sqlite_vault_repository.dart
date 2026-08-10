import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';

class SqliteVaultRepository implements VaultRepository {
  SqliteVaultRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  @override
  Future<Vault?> getDefaultVault() {
    return _database.run((db) async {
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
    });
  }

  @override
  Future<List<Vault>> listAll() {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.vaults,
        orderBy: 'created_at ASC',
      );
      return rows.map(_mapVault).toList(growable: false);
    });
  }

  @override
  Future<void> save(Vault vault) {
    return _database.transaction((executor) async {
      final existing = await executor.query(
        DatabaseSchema.vaults,
        columns: const <String>['is_default'],
        where: 'id = ?',
        whereArgs: <Object>[vault.id],
        limit: 1,
      );
      if (!vault.isDefault &&
          existing.isNotEmpty &&
          existing.single['is_default'] == 1) {
        throw StateError('vault_default_required');
      }
      if (vault.isDefault) {
        await executor.update(
          DatabaseSchema.vaults,
          const <String, Object?>{'is_default': 0},
          where: 'is_default = 1 AND id != ?',
          whereArgs: <Object>[vault.id],
        );
      }
      await executor.rawInsert(
        '''
        INSERT INTO ${DatabaseSchema.vaults} (
          id,
          name,
          description,
          is_default,
          encryption_version,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          description = excluded.description,
          is_default = excluded.is_default,
          encryption_version = excluded.encryption_version,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          vault.id,
          vault.name,
          vault.description,
          vault.isDefault ? 1 : 0,
          vault.encryptionVersion,
          vault.createdAt.millisecondsSinceEpoch,
          vault.updatedAt.millisecondsSinceEpoch,
        ],
      );
      final defaults = await executor.rawQuery('''
        SELECT COUNT(*) AS count
        FROM ${DatabaseSchema.vaults}
        WHERE is_default = 1
        ''');
      if (defaults.single['count'] != 1) {
        throw StateError('vault_default_required');
      }
    });
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
