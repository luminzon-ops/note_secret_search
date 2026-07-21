import 'dart:convert';

import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';

class SqliteModelRegistryRepository implements ModelRegistryRepository {
  SqliteModelRegistryRepository({
    required AppDatabase database,
    void Function()? beforeMutation,
  }) : _database = database,
       _beforeMutation = beforeMutation;

  final AppDatabase _database;
  final void Function()? _beforeMutation;

  @override
  Future<ModelRegistryEntry?> getById(String id) {
    return _database.run((db) async {
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
    });
  }

  @override
  Future<void> deleteById(String id) {
    _beforeMutation?.call();
    return _database.run((db) async {
      await db.delete(
        DatabaseSchema.modelRegistry,
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
    });
  }

  @override
  Future<List<ModelRegistryEntry>> listInstalledModels() {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.modelRegistry,
        orderBy: 'installed_at DESC, id ASC',
      );
      return rows.map(_mapEntry).toList(growable: false);
    });
  }

  @override
  Future<void> save(ModelRegistryEntry entry) {
    _beforeMutation?.call();
    return _database.run((db) async {
      await db.rawInsert(
        '''
        INSERT INTO ${DatabaseSchema.modelRegistry} (
          id,
          type,
          provider,
          name,
          version,
          size_bytes,
          quantization,
          min_ram_mb,
          recommended_tier,
          local_path,
          artifact_paths_json,
          checksum,
          integrity_status,
          enabled,
          installed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          type = excluded.type,
          provider = excluded.provider,
          name = excluded.name,
          version = excluded.version,
          size_bytes = excluded.size_bytes,
          quantization = excluded.quantization,
          min_ram_mb = excluded.min_ram_mb,
          recommended_tier = excluded.recommended_tier,
          local_path = excluded.local_path,
          artifact_paths_json = excluded.artifact_paths_json,
          checksum = excluded.checksum,
          integrity_status = excluded.integrity_status,
          enabled = excluded.enabled,
          installed_at = excluded.installed_at
        ''',
        <Object?>[
          entry.id,
          entry.type,
          entry.provider,
          entry.name,
          entry.version,
          entry.sizeBytes,
          entry.quantization,
          entry.minRamMb,
          entry.recommendedTier,
          entry.localPath,
          encodeModelArtifactPathsForSqlite(entry.artifacts),
          entry.checksum,
          entry.integrityStatus.name,
          entry.enabled ? 1 : 0,
          entry.installedAt?.millisecondsSinceEpoch,
        ],
      );
    });
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
      artifacts: decodeModelArtifactPathsFromSqlite(
        row['artifact_paths_json'] as String?,
      ),
      checksum: row['checksum'] as String?,
      enabled: (row['enabled'] as int? ?? 0) == 1,
      installedAt: row['installed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['installed_at']! as int),
      filePresent: true,
      integrityStatus: _parseIntegrityStatus(
        row['integrity_status'] as String?,
      ),
    );
  }

  ModelIntegrityStatus _parseIntegrityStatus(String? raw) {
    return ModelIntegrityStatus.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ModelIntegrityStatus.unknown,
    );
  }
}

String encodeModelArtifactPathsForSqlite(List<ModelArtifactPath> artifacts) {
  return jsonEncode(
    artifacts.map((artifact) => artifact.toJson()).toList(growable: false),
  );
}

List<ModelArtifactPath> decodeModelArtifactPathsFromSqlite(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <ModelArtifactPath>[];
  }
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    return const <ModelArtifactPath>[];
  }
  return decoded
      .whereType<Map<String, dynamic>>()
      .map(ModelArtifactPath.fromJson)
      .toList(growable: false);
}
