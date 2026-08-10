import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum LegacyFixtureVersion {
  v1,
  v2,
  upgradedV3,
  freshV3,
  upgradedV4,
  freshV4,
  phase2MigratedV4,
}

const legacyMigrationSourceVersions = <LegacyFixtureVersion>[
  LegacyFixtureVersion.v1,
  LegacyFixtureVersion.v2,
  LegacyFixtureVersion.upgradedV3,
  LegacyFixtureVersion.freshV3,
];

extension LegacyFixtureVersionSchema on LegacyFixtureVersion {
  int get schemaVersion => switch (this) {
    LegacyFixtureVersion.v1 => 1,
    LegacyFixtureVersion.v2 => 2,
    LegacyFixtureVersion.upgradedV3 || LegacyFixtureVersion.freshV3 => 3,
    LegacyFixtureVersion.upgradedV4 ||
    LegacyFixtureVersion.freshV4 ||
    LegacyFixtureVersion.phase2MigratedV4 => 4,
  };
}

Future<void> createHistoricalDatabaseSchema(
  Database database,
  LegacyFixtureVersion version,
) async {
  final freshSchema =
      version == LegacyFixtureVersion.freshV3 ||
      version == LegacyFixtureVersion.freshV4 ||
      version == LegacyFixtureVersion.phase2MigratedV4;
  for (final statement in _baseStatements(freshModelRegistry: freshSchema)) {
    await database.execute(statement);
  }
  if (version != LegacyFixtureVersion.v1) {
    for (final statement in _chatStatements) {
      await database.execute(statement);
    }
  }
  if (version == LegacyFixtureVersion.upgradedV3 ||
      version == LegacyFixtureVersion.upgradedV4) {
    await database.execute(
      'ALTER TABLE model_registry ADD COLUMN artifact_paths_json TEXT',
    );
  }
  if (version.schemaVersion == 4) {
    await database.execute(_securityMetadataStatement);
  }
}

List<String> _baseStatements({required bool freshModelRegistry}) => <String>[
  '''
  CREATE TABLE vaults (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    is_default INTEGER NOT NULL DEFAULT 0,
    encryption_version INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE secret_items (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    title TEXT NOT NULL,
    username_ciphertext BLOB,
    password_ciphertext BLOB,
    website_url_ciphertext BLOB,
    note_ciphertext BLOB,
    category_id TEXT,
    favorite INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_accessed_at INTEGER,
    deleted_at INTEGER
  )
  ''',
  '''
  CREATE TABLE note_items (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    title TEXT NOT NULL,
    content_ciphertext BLOB NOT NULL,
    summary_ciphertext BLOB,
    category_id TEXT,
    favorite INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )
  ''',
  '''
  CREATE TABLE tags (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE item_tags (
    item_id TEXT NOT NULL,
    item_type TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    PRIMARY KEY (item_id, item_type, tag_id)
  )
  ''',
  '''
  CREATE TABLE categories (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE embedding_chunks (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    source_type TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    plaintext_hash TEXT NOT NULL,
    model_id TEXT NOT NULL,
    vector_blob BLOB,
    token_count INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  freshModelRegistry ? _freshModelRegistryStatement : _v1ModelRegistryStatement,
  '''
  CREATE TABLE model_catalog_entries (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    tier TEXT NOT NULL,
    display_name TEXT NOT NULL,
    description TEXT,
    quantization TEXT,
    size_bytes INTEGER,
    min_ram_mb INTEGER,
    recommended_tier TEXT,
    speed_hint TEXT,
    quality_hint TEXT,
    license TEXT,
    release_date TEXT,
    source_list_json TEXT,
    checksum TEXT,
    signature TEXT,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE download_tasks (
    id TEXT PRIMARY KEY,
    model_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    status TEXT NOT NULL,
    total_bytes INTEGER,
    downloaded_bytes INTEGER,
    average_speed REAL,
    error_message TEXT,
    resumable INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE provider_configs (
    id TEXT PRIMARY KEY,
    provider_type TEXT NOT NULL,
    name TEXT NOT NULL,
    encrypted_config BLOB NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE sync_accounts (
    id TEXT PRIMARY KEY,
    provider_type TEXT NOT NULL,
    encrypted_config BLOB NOT NULL,
    last_sync_at INTEGER,
    status TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value_ciphertext BLOB NOT NULL
  )
  ''',
];

const _v1ModelRegistryStatement = '''
  CREATE TABLE model_registry (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    provider TEXT NOT NULL,
    name TEXT NOT NULL,
    version TEXT,
    size_bytes INTEGER,
    quantization TEXT,
    min_ram_mb INTEGER,
    recommended_tier TEXT,
    local_path TEXT,
    checksum TEXT,
    enabled INTEGER NOT NULL DEFAULT 0,
    installed_at INTEGER
  )
  ''';

const _freshModelRegistryStatement = '''
  CREATE TABLE model_registry (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    provider TEXT NOT NULL,
    name TEXT NOT NULL,
    version TEXT,
    size_bytes INTEGER,
    quantization TEXT,
    min_ram_mb INTEGER,
    recommended_tier TEXT,
    local_path TEXT,
    artifact_paths_json TEXT,
    checksum TEXT,
    integrity_status TEXT NOT NULL DEFAULT 'unknown',
    enabled INTEGER NOT NULL DEFAULT 0,
    installed_at INTEGER
  )
  ''';

const _chatStatements = <String>[
  '''
  CREATE TABLE chat_sessions (
    id TEXT PRIMARY KEY,
    mode TEXT NOT NULL,
    title TEXT NOT NULL,
    allow_private_context INTEGER NOT NULL DEFAULT 0,
    last_model_id TEXT,
    archived INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE chat_messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT NOT NULL,
    used_private_context INTEGER NOT NULL DEFAULT 0,
    auto_retrieved_context_summary TEXT,
    manual_context_item_ids_json TEXT,
    related_source_ids_json TEXT,
    created_at INTEGER NOT NULL
  )
  ''',
];

const _securityMetadataStatement = '''
  CREATE TABLE security_metadata (
    key_id TEXT PRIMARY KEY,
    source_schema_version INTEGER NOT NULL,
    field_envelope_version INTEGER NOT NULL,
    migration_state TEXT NOT NULL,
    migrated_at INTEGER NOT NULL
  )
  ''';
