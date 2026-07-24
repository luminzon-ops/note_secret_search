class ModelCatalogStateRecord {
  const ModelCatalogStateRecord({
    required this.id,
    required this.acceptedVersion,
    required this.acceptedDigest,
    required this.acceptedKeyId,
    required this.acceptedSchemaVersion,
    required this.minimumAcceptedVersion,
    required this.updatedAt,
  });

  final String id;
  final int acceptedVersion;
  final String acceptedDigest;
  final String acceptedKeyId;
  final int acceptedSchemaVersion;
  final int minimumAcceptedVersion;
  final int updatedAt;
}

class ModelRegistryArtifactRecord {
  const ModelRegistryArtifactRecord({
    required this.modelId,
    required this.releaseId,
    required this.artifactId,
    required this.role,
    required this.required,
    required this.relativePath,
    required this.expectedSizeBytes,
    required this.expectedSha256,
    this.verifiedSizeBytes,
    this.verifiedSha256,
    this.sourceId,
    required this.state,
    this.verifiedAt,
  });

  final String modelId;
  final String releaseId;
  final String artifactId;
  final String role;
  final bool required;
  final String relativePath;
  final int expectedSizeBytes;
  final String expectedSha256;
  final int? verifiedSizeBytes;
  final String? verifiedSha256;
  final String? sourceId;
  final String state;
  final int? verifiedAt;
}

class ModelDownloadCheckpointRecord {
  const ModelDownloadCheckpointRecord({
    required this.taskId,
    required this.modelId,
    required this.sourceId,
    required this.status,
    this.operationId,
    required this.attemptGeneration,
    this.releaseId,
    this.artifactId,
    this.sourceUrl,
    this.stagingPath,
    this.expectedSha256,
    this.expectedSizeBytes,
    this.etag,
    this.lastModified,
    required this.checkpoint,
    this.retryReason,
    required this.receivedBytes,
    required this.createdAt,
    required this.updatedAt,
    this.resumable = true,
  });

  final String taskId;
  final String modelId;
  final String sourceId;
  final String status;
  final String? operationId;
  final int attemptGeneration;
  final String? releaseId;
  final String? artifactId;
  final String? sourceUrl;
  final String? stagingPath;
  final String? expectedSha256;
  final int? expectedSizeBytes;
  final String? etag;
  final String? lastModified;
  final String checkpoint;
  final String? retryReason;
  final int receivedBytes;
  final int createdAt;
  final int updatedAt;
  final bool resumable;

  ModelDownloadCheckpointRecord copyWith({
    String? checkpoint,
    String? retryReason,
    bool clearRetryReason = false,
    int? receivedBytes,
    int? updatedAt,
  }) {
    return ModelDownloadCheckpointRecord(
      taskId: taskId,
      modelId: modelId,
      sourceId: sourceId,
      status: status,
      operationId: operationId,
      attemptGeneration: attemptGeneration,
      releaseId: releaseId,
      artifactId: artifactId,
      sourceUrl: sourceUrl,
      stagingPath: stagingPath,
      expectedSha256: expectedSha256,
      expectedSizeBytes: expectedSizeBytes,
      etag: etag,
      lastModified: lastModified,
      checkpoint: checkpoint ?? this.checkpoint,
      retryReason: clearRetryReason ? null : (retryReason ?? this.retryReason),
      receivedBytes: receivedBytes ?? this.receivedBytes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resumable: resumable,
    );
  }
}

class ModelInstallJournalRecord {
  const ModelInstallJournalRecord({
    required this.operationId,
    required this.modelId,
    this.releaseId,
    required this.attemptGeneration,
    required this.operationType,
    required this.phase,
    this.oldRevision,
    this.newRevision,
    this.stagingRoot,
    this.targetRoot,
    this.errorCode,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String operationId;
  final String modelId;
  final String? releaseId;
  final int attemptGeneration;
  final String operationType;
  final String phase;
  final String? oldRevision;
  final String? newRevision;
  final String? stagingRoot;
  final String? targetRoot;
  final String? errorCode;
  final int createdAt;
  final int updatedAt;
  final int? completedAt;
}

ModelCatalogStateRecord catalogStateFromRow(Map<String, Object?> row) {
  return ModelCatalogStateRecord(
    id: row['id']! as String,
    acceptedVersion: row['accepted_version']! as int,
    acceptedDigest: row['accepted_digest']! as String,
    acceptedKeyId: row['accepted_key_id']! as String,
    acceptedSchemaVersion: row['accepted_schema_version']! as int,
    minimumAcceptedVersion: row['minimum_accepted_version']! as int,
    updatedAt: row['updated_at']! as int,
  );
}

ModelRegistryArtifactRecord artifactFromRow(Map<String, Object?> row) {
  return ModelRegistryArtifactRecord(
    modelId: row['model_id']! as String,
    releaseId: row['release_id']! as String,
    artifactId: row['artifact_id']! as String,
    role: row['role']! as String,
    required: (row['required'] as int? ?? 0) == 1,
    relativePath: row['relative_path']! as String,
    expectedSizeBytes: row['expected_size_bytes']! as int,
    expectedSha256: row['expected_sha256']! as String,
    verifiedSizeBytes: row['verified_size_bytes'] as int?,
    verifiedSha256: row['verified_sha256'] as String?,
    sourceId: row['source_id'] as String?,
    state: row['state']! as String,
    verifiedAt: row['verified_at'] as int?,
  );
}

ModelDownloadCheckpointRecord checkpointFromRow(Map<String, Object?> row) {
  return ModelDownloadCheckpointRecord(
    taskId: row['id']! as String,
    modelId: row['model_id']! as String,
    sourceId: row['source_id']! as String,
    status: row['status']! as String,
    operationId: row['operation_id'] as String?,
    attemptGeneration: row['attempt_generation']! as int,
    releaseId: row['release_id'] as String?,
    artifactId: row['artifact_id'] as String?,
    sourceUrl: row['source_url'] as String?,
    stagingPath: row['staging_path'] as String?,
    expectedSha256: row['expected_sha256'] as String?,
    expectedSizeBytes: row['expected_size_bytes'] as int?,
    etag: row['etag'] as String?,
    lastModified: row['last_modified'] as String?,
    checkpoint: row['checkpoint']! as String,
    retryReason: row['retry_reason'] as String?,
    receivedBytes: row['received_bytes']! as int,
    createdAt: row['created_at']! as int,
    updatedAt: row['updated_at']! as int,
    resumable: (row['resumable'] as int? ?? 1) == 1,
  );
}

ModelInstallJournalRecord journalFromRow(Map<String, Object?> row) {
  return ModelInstallJournalRecord(
    operationId: row['operation_id']! as String,
    modelId: row['model_id']! as String,
    releaseId: row['release_id'] as String?,
    attemptGeneration: row['attempt_generation']! as int,
    operationType: row['operation_type']! as String,
    phase: row['phase']! as String,
    oldRevision: row['old_revision'] as String?,
    newRevision: row['new_revision'] as String?,
    stagingRoot: row['staging_root'] as String?,
    targetRoot: row['target_root'] as String?,
    errorCode: row['error_code'] as String?,
    createdAt: row['created_at']! as int,
    updatedAt: row['updated_at']! as int,
    completedAt: row['completed_at'] as int?,
  );
}
