abstract final class DatabaseSchemaV8 {
  static const String catalogStateTable = 'model_catalog_state';
  static const String registryArtifactsTable = 'model_registry_artifacts';
  static const String installJournalTable = 'model_install_journal';

  static const String catalogStateCreateStatement = '''
    CREATE TABLE IF NOT EXISTS model_catalog_state (
      id TEXT PRIMARY KEY,
      accepted_version INTEGER NOT NULL
        CHECK (accepted_version >= 1),
      accepted_digest TEXT NOT NULL
        CHECK (
          length(accepted_digest) = 64
          AND accepted_digest NOT GLOB '*[^0-9a-f]*'
        ),
      accepted_key_id TEXT NOT NULL
        CHECK (length(accepted_key_id) > 0),
      accepted_schema_version INTEGER NOT NULL
        CHECK (accepted_schema_version >= 1),
      minimum_accepted_version INTEGER NOT NULL DEFAULT 1
        CHECK (
          minimum_accepted_version >= 1
          AND minimum_accepted_version <= accepted_version
        ),
      updated_at INTEGER NOT NULL
    )
    ''';

  static const String registryArtifactsCreateStatement = '''
    CREATE TABLE IF NOT EXISTS model_registry_artifacts (
      model_id TEXT NOT NULL
        REFERENCES model_registry(id) ON DELETE CASCADE,
      release_id TEXT NOT NULL,
      artifact_id TEXT NOT NULL,
      role TEXT NOT NULL,
      required INTEGER NOT NULL DEFAULT 1
        CHECK (required IN (0, 1)),
      relative_path TEXT NOT NULL COLLATE NOCASE
        CHECK (
          length(relative_path) > 0
          AND substr(relative_path, 1, 1) <> '/'
          AND substr(relative_path, -1, 1) <> '/'
          AND instr(relative_path, char(92)) = 0
          AND instr(relative_path, ':') = 0
          AND instr(relative_path, '//') = 0
          AND relative_path <> '.'
          AND relative_path <> '..'
          AND relative_path NOT LIKE './%'
          AND relative_path NOT LIKE '../%'
          AND relative_path NOT LIKE '%/./%'
          AND relative_path NOT LIKE '%/../%'
          AND relative_path NOT LIKE '%/.'
          AND relative_path NOT LIKE '%/..'
        ),
      expected_size_bytes INTEGER NOT NULL
        CHECK (expected_size_bytes >= 0),
      expected_sha256 TEXT NOT NULL
        CHECK (
          length(expected_sha256) = 71
          AND substr(expected_sha256, 1, 7) = 'sha256:'
          AND substr(expected_sha256, 8) NOT GLOB '*[^0-9a-f]*'
        ),
      verified_size_bytes INTEGER
        CHECK (verified_size_bytes IS NULL OR verified_size_bytes >= 0),
      verified_sha256 TEXT
        CHECK (
          verified_sha256 IS NULL
          OR (
            length(verified_sha256) = 71
            AND substr(verified_sha256, 1, 7) = 'sha256:'
            AND substr(verified_sha256, 8) NOT GLOB '*[^0-9a-f]*'
          )
        ),
      source_id TEXT,
      state TEXT NOT NULL DEFAULT 'unknown'
        CHECK (
          state IN (
            'unknown',
            'verified',
            'corrupted',
            'staged',
            'installed',
            'orphaned'
          )
        ),
      verified_at INTEGER,
      PRIMARY KEY (model_id, release_id, artifact_id),
      UNIQUE (model_id, release_id, relative_path)
    )
    ''';

  static const String installJournalCreateStatement = '''
    CREATE TABLE IF NOT EXISTS model_install_journal (
      operation_id TEXT PRIMARY KEY,
      model_id TEXT NOT NULL,
      release_id TEXT,
      attempt_generation INTEGER NOT NULL DEFAULT 0
        CHECK (attempt_generation >= 0),
      operation_type TEXT NOT NULL
        CHECK (operation_type IN ('install', 'replace', 'repair', 'delete')),
      phase TEXT NOT NULL
        CHECK (
          phase IN (
            'queued',
            'staging',
            'verifying',
            'staged',
            'runtime_validating',
            'releasing_sessions',
            'installing',
            'committing',
            'completed',
            'rollback_pending',
            'failed',
            'deleting'
          )
        ),
      old_revision TEXT,
      new_revision TEXT,
      staging_root TEXT,
      target_root TEXT,
      error_code TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      completed_at INTEGER
    )
    ''';

  static const String addOperationIdStatement =
      'ALTER TABLE download_tasks ADD COLUMN operation_id TEXT';
  static const String addAttemptGenerationStatement =
      'ALTER TABLE download_tasks ADD COLUMN attempt_generation INTEGER '
      'NOT NULL DEFAULT 0 CHECK (attempt_generation >= 0)';
  static const String addReleaseIdStatement =
      'ALTER TABLE download_tasks ADD COLUMN release_id TEXT';
  static const String addArtifactIdStatement =
      'ALTER TABLE download_tasks ADD COLUMN artifact_id TEXT';
  static const String addSourceUrlStatement =
      'ALTER TABLE download_tasks ADD COLUMN source_url TEXT';
  static const String addStagingPathStatement =
      'ALTER TABLE download_tasks ADD COLUMN staging_path TEXT';
  static const String addExpectedSha256Statement =
      'ALTER TABLE download_tasks ADD COLUMN expected_sha256 TEXT '
      'CHECK ('
      'expected_sha256 IS NULL OR ('
      'length(expected_sha256) = 71 '
      "AND substr(expected_sha256, 1, 7) = 'sha256:' "
      "AND substr(expected_sha256, 8) NOT GLOB '*[^0-9a-f]*'"
      '))';
  static const String addExpectedSizeBytesStatement =
      'ALTER TABLE download_tasks ADD COLUMN expected_size_bytes INTEGER '
      'CHECK (expected_size_bytes IS NULL OR expected_size_bytes >= 0)';
  static const String addEtagStatement =
      'ALTER TABLE download_tasks ADD COLUMN etag TEXT';
  static const String addLastModifiedStatement =
      'ALTER TABLE download_tasks ADD COLUMN last_modified TEXT';
  static const String addCheckpointStatement = '''
    ALTER TABLE download_tasks ADD COLUMN checkpoint TEXT NOT NULL
      DEFAULT 'legacy'
      CHECK (
        checkpoint IN (
          'legacy',
          'queued',
          'probing',
          'downloading',
          'paused',
          'verifying',
          'staged',
          'runtime_validating',
          'releasing_sessions',
          'installing',
          'committing',
          'completed',
          'retryable_failed',
          'failed'
        )
      )
    ''';
  static const String addRetryReasonStatement =
      'ALTER TABLE download_tasks ADD COLUMN retry_reason TEXT';
  static const String addReceivedBytesStatement =
      'ALTER TABLE download_tasks ADD COLUMN received_bytes INTEGER NOT NULL '
      'DEFAULT 0 CHECK (received_bytes >= 0)';
  static const String backfillReceivedBytesStatement = '''
    UPDATE download_tasks
    SET received_bytes = COALESCE(downloaded_bytes, 0)
    WHERE received_bytes = 0 AND COALESCE(downloaded_bytes, 0) > 0
    ''';

  static const String createRegistryArtifactsModelIndexStatement = '''
    CREATE INDEX IF NOT EXISTS idx_model_registry_artifacts_model_release
    ON model_registry_artifacts(model_id, release_id, state, artifact_id)
    ''';
  static const String createDownloadIdentityIndexStatement = '''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_download_tasks_identity
    ON download_tasks(operation_id, artifact_id, attempt_generation)
    WHERE operation_id IS NOT NULL AND artifact_id IS NOT NULL
    ''';
  static const String createDownloadOperationIndexStatement = '''
    CREATE INDEX IF NOT EXISTS idx_download_tasks_operation_checkpoint
    ON download_tasks(operation_id, attempt_generation, checkpoint, updated_at DESC)
    WHERE operation_id IS NOT NULL
    ''';
  static const String createInstallJournalModelIndexStatement = '''
    CREATE INDEX IF NOT EXISTS idx_model_install_journal_model_phase
    ON model_install_journal(model_id, phase, updated_at DESC)
    ''';

  static const Map<String, String> downloadTaskColumnStatements =
      <String, String>{
        'operation_id': addOperationIdStatement,
        'attempt_generation': addAttemptGenerationStatement,
        'release_id': addReleaseIdStatement,
        'artifact_id': addArtifactIdStatement,
        'source_url': addSourceUrlStatement,
        'staging_path': addStagingPathStatement,
        'expected_sha256': addExpectedSha256Statement,
        'expected_size_bytes': addExpectedSizeBytesStatement,
        'etag': addEtagStatement,
        'last_modified': addLastModifiedStatement,
        'checkpoint': addCheckpointStatement,
        'retry_reason': addRetryReasonStatement,
        'received_bytes': addReceivedBytesStatement,
      };

  static const List<String> migrationStatements = <String>[
    catalogStateCreateStatement,
    registryArtifactsCreateStatement,
    installJournalCreateStatement,
    addOperationIdStatement,
    addAttemptGenerationStatement,
    addReleaseIdStatement,
    addArtifactIdStatement,
    addSourceUrlStatement,
    addStagingPathStatement,
    addExpectedSha256Statement,
    addExpectedSizeBytesStatement,
    addEtagStatement,
    addLastModifiedStatement,
    addCheckpointStatement,
    addRetryReasonStatement,
    addReceivedBytesStatement,
    backfillReceivedBytesStatement,
    createRegistryArtifactsModelIndexStatement,
    createDownloadIdentityIndexStatement,
    createDownloadOperationIndexStatement,
    createInstallJournalModelIndexStatement,
  ];
}
