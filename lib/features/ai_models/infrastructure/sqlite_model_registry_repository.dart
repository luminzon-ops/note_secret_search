import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SqliteModelRegistryRepository implements ModelRegistryRepository {
  SqliteModelRegistryRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  @override
  Future<ModelRegistryEntry?> getById(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.modelRegistry,
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapEntry(rows.first);
  }

  @override
  Future<void> deleteById(String id) async {
    final db = await _database.database;
    await db.delete(
      DatabaseSchema.modelRegistry,
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() async {
    final db = await _database.database;
    final rows = await db.query(
      DatabaseSchema.modelRegistry,
      orderBy: 'installed_at DESC',
    );
    return rows.map(_mapEntry).toList(growable: false);
  }

  @override
  Future<void> save(ModelRegistryEntry entry) async {
    final db = await _database.database;
    await db.insert(
      DatabaseSchema.modelRegistry,
      <String, Object?>{
        'id': entry.id,
        'type': entry.type,
        'provider': entry.provider,
        'name': entry.name,
        'version': entry.version,
        'size_bytes': entry.sizeBytes,
        'quantization': entry.quantization,
        'min_ram_mb': entry.minRamMb,
        'recommended_tier': entry.recommendedTier,
        'local_path': entry.localPath,
        'checksum': entry.checksum,
        'enabled': entry.enabled ? 1 : 0,
        'installed_at': entry.installedAt?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  ModelRegistryEntry _mapEntry(Map<String, Object?> row) {
    return ModelRegistryEntry(
      id: row['id']! as String,
      type: row['type']! as String,
      provider: row['provider']! as String,
      name: row['name']! as String,
      version: row['version'] as String?,
      sizeBytes: row['size_bytes'] as int?,
      quantization: row['quantization'] as String?,
      minRamMb: row['min_ram_mb'] as int?,
      recommendedTier: row['recommended_tier'] as String?,
      localPath: row['local_path'] as String?,
      checksum: row['checksum'] as String?,
      enabled: (row['enabled'] as int? ?? 0) == 1,
      installedAt: row['installed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['installed_at']! as int),
      filePresent: true,
    );
  }
}
