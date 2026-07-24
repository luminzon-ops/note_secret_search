import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/model_state_records.dart';
import 'package:path/path.dart' as p;

export 'package:note_secret_search/core/storage/database/model_state_records.dart';

class SqliteModelStateRepository {
  SqliteModelStateRepository({required AppDatabase database})
    : _database = database;

  final AppDatabase _database;

  Future<void> saveCatalogState(ModelCatalogStateRecord state) {
    _requireText(state.id, 'id');
    _requireCatalogDigest(state.acceptedDigest, 'acceptedDigest');
    _requireText(state.acceptedKeyId, 'acceptedKeyId');
    if (state.acceptedVersion < 1 ||
        state.acceptedSchemaVersion < 1 ||
        state.minimumAcceptedVersion < 1 ||
        state.minimumAcceptedVersion > state.acceptedVersion) {
      throw ArgumentError.value(state, 'state');
    }
    return _database.transaction((db) async {
      final rows = await db.query(
        DatabaseSchema.modelCatalogState,
        where: 'id = ?',
        whereArgs: <Object>[state.id],
        limit: 1,
      );
      var minimumAcceptedVersion = state.minimumAcceptedVersion;
      if (rows.isNotEmpty) {
        final current = catalogStateFromRow(rows.single);
        if (state.acceptedVersion < current.acceptedVersion ||
            (state.acceptedVersion == current.acceptedVersion &&
                state.acceptedDigest != current.acceptedDigest)) {
          throw StateError('model_catalog_acceptance_conflict');
        }
        if (minimumAcceptedVersion < current.minimumAcceptedVersion) {
          minimumAcceptedVersion = current.minimumAcceptedVersion;
        }
      }
      await db.rawInsert(
        '''
        INSERT INTO ${DatabaseSchema.modelCatalogState} (
          id,
          accepted_version,
          accepted_digest,
          accepted_key_id,
          accepted_schema_version,
          minimum_accepted_version,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          accepted_version = excluded.accepted_version,
          accepted_digest = excluded.accepted_digest,
          accepted_key_id = excluded.accepted_key_id,
          accepted_schema_version = excluded.accepted_schema_version,
          minimum_accepted_version = excluded.minimum_accepted_version,
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          state.id,
          state.acceptedVersion,
          state.acceptedDigest,
          state.acceptedKeyId,
          state.acceptedSchemaVersion,
          minimumAcceptedVersion,
          state.updatedAt,
        ],
      );
    });
  }

  Future<ModelCatalogStateRecord?> loadCatalogState({String id = 'active'}) {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.modelCatalogState,
        where: 'id = ?',
        whereArgs: <Object>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : catalogStateFromRow(rows.single);
    });
  }

  Future<void> saveRegistryArtifact(ModelRegistryArtifactRecord artifact) {
    _requireText(artifact.modelId, 'modelId');
    _requireText(artifact.releaseId, 'releaseId');
    _requireText(artifact.artifactId, 'artifactId');
    _requireText(artifact.role, 'role');
    _requireRelativePath(artifact.relativePath, 'relativePath');
    _requireArtifactDigest(artifact.expectedSha256, 'expectedSha256');
    if (artifact.verifiedSha256 != null) {
      _requireArtifactDigest(artifact.verifiedSha256!, 'verifiedSha256');
    }
    if (artifact.expectedSizeBytes < 0) {
      throw ArgumentError.value(
        artifact.expectedSizeBytes,
        'expectedSizeBytes',
      );
    }
    return _database.run((db) {
      return db.rawInsert(
        '''
        INSERT INTO ${DatabaseSchema.modelRegistryArtifacts} (
          model_id,
          release_id,
          artifact_id,
          role,
          required,
          relative_path,
          expected_size_bytes,
          expected_sha256,
          verified_size_bytes,
          verified_sha256,
          source_id,
          state,
          verified_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(model_id, release_id, artifact_id) DO UPDATE SET
          role = excluded.role,
          required = excluded.required,
          relative_path = excluded.relative_path,
          expected_size_bytes = excluded.expected_size_bytes,
          expected_sha256 = excluded.expected_sha256,
          verified_size_bytes = excluded.verified_size_bytes,
          verified_sha256 = excluded.verified_sha256,
          source_id = excluded.source_id,
          state = excluded.state,
          verified_at = excluded.verified_at
        ''',
        <Object?>[
          artifact.modelId,
          artifact.releaseId,
          artifact.artifactId,
          artifact.role,
          artifact.required ? 1 : 0,
          artifact.relativePath,
          artifact.expectedSizeBytes,
          artifact.expectedSha256,
          artifact.verifiedSizeBytes,
          artifact.verifiedSha256,
          artifact.sourceId,
          artifact.state,
          artifact.verifiedAt,
        ],
      );
    });
  }

  Future<List<ModelRegistryArtifactRecord>> listRegistryArtifacts(
    String modelId, {
    String? releaseId,
  }) {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.modelRegistryArtifacts,
        where: releaseId == null
            ? 'model_id = ?'
            : 'model_id = ? AND release_id = ?',
        whereArgs: releaseId == null
            ? <Object>[modelId]
            : <Object>[modelId, releaseId],
        orderBy: 'release_id ASC, artifact_id ASC',
      );
      return rows.map(artifactFromRow).toList(growable: false);
    });
  }

  Future<void> saveDownloadCheckpoint(
    ModelDownloadCheckpointRecord checkpoint,
  ) {
    _requireText(checkpoint.taskId, 'taskId');
    _requireText(checkpoint.modelId, 'modelId');
    _requireText(checkpoint.sourceId, 'sourceId');
    if (checkpoint.expectedSha256 != null) {
      _requireArtifactDigest(checkpoint.expectedSha256!, 'expectedSha256');
    }
    if (checkpoint.attemptGeneration < 0 || checkpoint.receivedBytes < 0) {
      throw ArgumentError.value(checkpoint, 'checkpoint');
    }
    return _database.run((db) {
      return db.rawInsert(
        '''
        INSERT INTO ${DatabaseSchema.downloadTasks} (
          id,
          model_id,
          source_id,
          status,
          total_bytes,
          downloaded_bytes,
          average_speed,
          error_message,
          resumable,
          created_at,
          updated_at,
          operation_id,
          attempt_generation,
          release_id,
          artifact_id,
          source_url,
          staging_path,
          expected_sha256,
          expected_size_bytes,
          etag,
          last_modified,
          checkpoint,
          retry_reason,
          received_bytes
        ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          model_id = excluded.model_id,
          source_id = excluded.source_id,
          status = excluded.status,
          total_bytes = excluded.total_bytes,
          downloaded_bytes = excluded.downloaded_bytes,
          error_message = excluded.error_message,
          resumable = excluded.resumable,
          updated_at = excluded.updated_at,
          operation_id = excluded.operation_id,
          attempt_generation = excluded.attempt_generation,
          release_id = excluded.release_id,
          artifact_id = excluded.artifact_id,
          source_url = excluded.source_url,
          staging_path = excluded.staging_path,
          expected_sha256 = excluded.expected_sha256,
          expected_size_bytes = excluded.expected_size_bytes,
          etag = excluded.etag,
          last_modified = excluded.last_modified,
          checkpoint = excluded.checkpoint,
          retry_reason = excluded.retry_reason,
          received_bytes = excluded.received_bytes
        ''',
        <Object?>[
          checkpoint.taskId,
          checkpoint.modelId,
          checkpoint.sourceId,
          checkpoint.status,
          checkpoint.expectedSizeBytes,
          checkpoint.receivedBytes,
          checkpoint.retryReason,
          checkpoint.resumable ? 1 : 0,
          checkpoint.createdAt,
          checkpoint.updatedAt,
          checkpoint.operationId,
          checkpoint.attemptGeneration,
          checkpoint.releaseId,
          checkpoint.artifactId,
          checkpoint.sourceUrl,
          checkpoint.stagingPath,
          checkpoint.expectedSha256,
          checkpoint.expectedSizeBytes,
          checkpoint.etag,
          checkpoint.lastModified,
          checkpoint.checkpoint,
          checkpoint.retryReason,
          checkpoint.receivedBytes,
        ],
      );
    });
  }

  Future<ModelDownloadCheckpointRecord?> loadDownloadCheckpoint(String taskId) {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.downloadTasks,
        where: 'id = ?',
        whereArgs: <Object>[taskId],
        limit: 1,
      );
      return rows.isEmpty ? null : checkpointFromRow(rows.single);
    });
  }

  Future<void> saveInstallJournal(ModelInstallJournalRecord journal) {
    _requireText(journal.operationId, 'operationId');
    _requireText(journal.modelId, 'modelId');
    if (journal.attemptGeneration < 0) {
      throw ArgumentError.value(journal.attemptGeneration, 'attemptGeneration');
    }
    return _database.run((db) {
      return db.rawInsert(
        '''
        INSERT INTO ${DatabaseSchema.modelInstallJournal} (
          operation_id,
          model_id,
          release_id,
          attempt_generation,
          operation_type,
          phase,
          old_revision,
          new_revision,
          staging_root,
          target_root,
          error_code,
          created_at,
          updated_at,
          completed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(operation_id) DO UPDATE SET
          model_id = excluded.model_id,
          release_id = excluded.release_id,
          attempt_generation = excluded.attempt_generation,
          operation_type = excluded.operation_type,
          phase = excluded.phase,
          old_revision = excluded.old_revision,
          new_revision = excluded.new_revision,
          staging_root = excluded.staging_root,
          target_root = excluded.target_root,
          error_code = excluded.error_code,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          completed_at = excluded.completed_at
        ''',
        <Object?>[
          journal.operationId,
          journal.modelId,
          journal.releaseId,
          journal.attemptGeneration,
          journal.operationType,
          journal.phase,
          journal.oldRevision,
          journal.newRevision,
          journal.stagingRoot,
          journal.targetRoot,
          journal.errorCode,
          journal.createdAt,
          journal.updatedAt,
          journal.completedAt,
        ],
      );
    });
  }

  Future<ModelInstallJournalRecord?> loadInstallJournal(String operationId) {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.modelInstallJournal,
        where: 'operation_id = ?',
        whereArgs: <Object>[operationId],
        limit: 1,
      );
      return rows.isEmpty ? null : journalFromRow(rows.single);
    });
  }

  Future<List<ModelInstallJournalRecord>> listOpenInstallJournals() {
    return _database.run((db) async {
      final rows = await db.query(
        DatabaseSchema.modelInstallJournal,
        where: 'completed_at IS NULL',
        orderBy: 'updated_at ASC, operation_id ASC',
      );
      return rows.map(journalFromRow).toList(growable: false);
    });
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Value is required.');
  }
}

void _requireCatalogDigest(String value, String name) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'Lowercase SHA-256 is required.');
  }
}

void _requireArtifactDigest(String value, String name) {
  if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'A sha256:<64 lowercase hex> digest is required.',
    );
  }
}

void _requireRelativePath(String value, String name) {
  _requireText(value, name);
  final segments = p.posix.split(value);
  if (value.contains(r'\') ||
      value.contains(':') ||
      p.posix.isAbsolute(value) ||
      p.windows.isAbsolute(value) ||
      p.posix.normalize(value) != value ||
      segments.any((segment) => segment == '.' || segment == '..') ||
      value.endsWith('/')) {
    throw ArgumentError.value(
      value,
      name,
      'A normalized relative path is required.',
    );
  }
}
