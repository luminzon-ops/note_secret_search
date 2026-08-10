import 'dart:convert';
import 'dart:io';

import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/ai_models/domain/model_artifact_path.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqlite_api.dart';

part 'sqlite_model_registry_support.dart';

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
      return rows.isEmpty ? null : _mapEntry(db, rows.single);
    });
  }

  @override
  Future<void> deleteById(String id) {
    _beforeMutation?.call();
    return _database.run((db) {
      return db.delete(
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
      return Future.wait(rows.map((row) => _mapEntry(db, row)));
    });
  }

  @override
  Future<void> save(ModelRegistryEntry entry) {
    _beforeMutation?.call();
    return _database.transaction((db) async {
      await writeModelRegistryEntry(db, entry);
    });
  }

  Future<ModelRegistryEntry> _mapEntry(
    DatabaseExecutor database,
    Map<String, Object?> row,
  ) async {
    final legacyArtifacts = _decodeArtifactsOrEmpty(
      row['artifact_paths_json'] as String?,
    );
    final hasTrustedProvenance = _rowHasTrustedProvenance(row);
    final activeReleaseId = row['active_release_id'] as String?;
    final normalizedRows = hasTrustedProvenance && activeReleaseId != null
        ? await database.query(
            DatabaseSchema.modelRegistryArtifacts,
            where: 'model_id = ? AND release_id = ?',
            whereArgs: <Object>[row['id']!, activeReleaseId],
            orderBy: 'artifact_id ASC',
          )
        : const <Map<String, Object?>>[];
    final artifacts = hasTrustedProvenance
        ? normalizedRows
              .map(
                (artifact) => _mapNormalizedArtifact(
                  artifact,
                  primaryPath: row['local_path'] as String?,
                  legacyArtifacts: legacyArtifacts,
                ),
              )
              .toList(growable: false)
        : _cleanupArtifacts(legacyArtifacts);
    final complete =
        hasTrustedProvenance &&
        _hasCompleteArtifactSet(
          artifacts,
          releaseId: activeReleaseId!,
          requireInstalled: true,
        );
    final filePresent =
        complete &&
        await _requiredFilesPresent(
          primaryPath: row['local_path'] as String?,
          artifacts: artifacts,
        );
    final integrity = complete
        ? _parseIntegrityStatus(row['integrity_status'] as String?)
        : ModelIntegrityStatus.unknown;
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
      artifacts: artifacts,
      checksum: row['checksum'] as String?,
      enabled: complete && (row['enabled'] as int? ?? 0) == 1,
      installedAt: row['installed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['installed_at']! as int),
      filePresent: filePresent,
      integrityStatus: integrity,
      releaseId: complete ? activeReleaseId : null,
      catalogVersion: complete ? row['catalog_version'] as int? : null,
      catalogDigest: complete ? row['catalog_digest'] as String? : null,
      generation: complete ? row['install_generation'] as int? : null,
      revisionRoot: complete ? row['revision_root'] as String? : null,
    );
  }
}

/// Writes a complete signed revision transactionally. A stale generation is
/// intentionally ignored so late callbacks cannot overwrite the active model.
Future<bool> writeModelRegistryEntry(
  DatabaseExecutor database,
  ModelRegistryEntry entry,
) async {
  final prepared = _prepareForStorage(entry);
  final existing = await database.query(
    DatabaseSchema.modelRegistry,
    where: 'id = ?',
    whereArgs: <Object>[prepared.id],
    limit: 1,
  );
  if (existing.isNotEmpty && !_canAdvance(existing.single, prepared)) {
    return false;
  }

  if (!_hasTrustedProvenance(prepared)) {
    await _writeParent(database, prepared);
    await database.delete(
      DatabaseSchema.modelRegistryArtifacts,
      where: 'model_id = ?',
      whereArgs: <Object>[prepared.id],
    );
    return true;
  }

  // The trigger permits this staging parent while artifact rows are replaced.
  await _writeParent(
    database,
    prepared.copyWith(
      enabled: false,
      integrityStatus: ModelIntegrityStatus.unknown,
    ),
  );
  await replaceNormalizedRegistryArtifacts(database, prepared);
  await _writeParent(database, prepared);
  return true;
}

Future<void> replaceNormalizedRegistryArtifacts(
  DatabaseExecutor database,
  ModelRegistryEntry entry,
) async {
  _validateTrustedEntry(entry);
  await database.delete(
    DatabaseSchema.modelRegistryArtifacts,
    where: 'model_id = ?',
    whereArgs: <Object>[entry.id],
  );
  for (final artifact in entry.artifacts) {
    await database
        .insert(DatabaseSchema.modelRegistryArtifacts, <String, Object?>{
          'model_id': entry.id,
          'release_id': entry.releaseId,
          'artifact_id': artifact.artifactId,
          'role': artifact.role,
          'required': artifact.required ? 1 : 0,
          'relative_path': artifact.relativePath,
          'expected_size_bytes': artifact.effectiveExpectedSizeBytes,
          'expected_sha256': artifact.effectiveExpectedChecksum,
          'verified_size_bytes': artifact.effectiveVerifiedSizeBytes,
          'verified_sha256': artifact.effectiveVerifiedChecksum,
          'source_id': artifact.sourceId.isEmpty ? null : artifact.sourceId,
          'state': artifact.state,
          'verified_at': artifact.verifiedAt,
        });
  }
}

Future<void> _writeParent(DatabaseExecutor database, ModelRegistryEntry entry) {
  return database.rawInsert(
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
      installed_at,
      active_release_id,
      catalog_version,
      catalog_digest,
      install_generation,
      revision_root
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      installed_at = excluded.installed_at,
      active_release_id = excluded.active_release_id,
      catalog_version = excluded.catalog_version,
      catalog_digest = excluded.catalog_digest,
      install_generation = excluded.install_generation,
      revision_root = excluded.revision_root
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
      entry.releaseId,
      entry.catalogVersion,
      entry.catalogDigest,
      entry.generation ?? 0,
      entry.revisionRoot,
    ],
  );
}

ModelRegistryEntry _prepareForStorage(ModelRegistryEntry entry) {
  if (!_hasAnyProvenance(entry)) {
    return entry.copyWith(
      enabled: false,
      integrityStatus: ModelIntegrityStatus.unknown,
      clearReleaseId: true,
      clearCatalogVersion: true,
      clearCatalogDigest: true,
      clearGeneration: true,
      clearRevisionRoot: true,
    );
  }
  _validateTrustedEntry(entry);
  return entry;
}

bool _canAdvance(Map<String, Object?> current, ModelRegistryEntry next) {
  final currentGeneration = current['install_generation'] as int? ?? 0;
  final nextGeneration = next.generation ?? 0;
  if (!_hasTrustedProvenance(next)) {
    return currentGeneration == 0;
  }
  if (nextGeneration != currentGeneration) {
    return nextGeneration > currentGeneration;
  }
  return current['active_release_id'] == next.releaseId &&
      current['catalog_version'] == next.catalogVersion &&
      current['catalog_digest'] == next.catalogDigest &&
      current['revision_root'] == next.revisionRoot;
}

bool _hasAnyProvenance(ModelRegistryEntry entry) {
  return entry.releaseId != null ||
      entry.catalogVersion != null ||
      entry.catalogDigest != null ||
      entry.generation != null ||
      entry.revisionRoot != null;
}
