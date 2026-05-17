import 'dart:convert';

import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_config.dart';
import 'package:note_secret_search/features/ai_providers/domain/external_provider_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteExternalProviderRepository implements ExternalProviderRepository {
  SqliteExternalProviderRepository({required AppDatabase database, required CryptoService cryptoService})
      : _database = database,
        _cryptoService = cryptoService;

  final AppDatabase _database;
  final CryptoService _cryptoService;

  @override
  Future<List<ExternalProviderConfig>> loadAll() async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.providerConfigs,
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapRow).toList(growable: false);
  }

  @override
  Future<ExternalProviderConfig?> loadById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.providerConfigs,
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapRow(rows.first);
  }

  @override
  Future<ExternalProviderConfig?> loadEnabled() async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.providerConfigs,
      where: 'enabled = ?',
      whereArgs: const <Object>[1],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapRow(rows.first);
  }

  @override
  Future<void> save(ExternalProviderConfig config) async {
    final db = await _database.database;
    final now = DateTime.now();
    final normalized = config.copyWith(
      createdAt: config.createdAt ?? now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      if (normalized.enabled) {
        await txn.update(
          DatabaseSchema.providerConfigs,
          <String, Object?>{'enabled': 0, 'updated_at': now.millisecondsSinceEpoch},
          where: 'provider_type = ?',
          whereArgs: <Object>[normalized.providerType.name],
        );
      }

      final encryptedConfig = _cryptoService.encryptNullable(jsonEncode(normalized.toJson()));
      if (encryptedConfig == null) {
        throw StateError('External provider config could not be encrypted.');
      }

      await txn.insert(
        DatabaseSchema.providerConfigs,
        <String, Object?>{
          'id': normalized.id,
          'provider_type': normalized.providerType.name,
          'name': normalized.displayName,
          'encrypted_config': encryptedConfig,
          'enabled': normalized.enabled ? 1 : 0,
          'created_at': normalized.createdAt?.millisecondsSinceEpoch,
          'updated_at': normalized.updatedAt?.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  ExternalProviderConfig _mapRow(Map<String, Object?> row) {
    final decrypted = _cryptoService.decryptNullable(row['encrypted_config'] as List<int>?);
    final decoded = jsonDecode(decrypted) as Map<String, Object?>;
    final config = ExternalProviderConfig.fromJson(decoded);
    return config.copyWith(
      providerType: ExternalProviderType.values.byName(row['provider_type']! as String),
      displayName: row['name']! as String,
      enabled: (row['enabled'] as int? ?? 0) == 1,
      createdAt: row['created_at'] == null
          ? config.createdAt
          : DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: row['updated_at'] == null
          ? config.updatedAt
          : DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    );
  }
}
