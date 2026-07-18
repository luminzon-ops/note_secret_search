import 'package:note_secret_search/core/storage/database/database_schema_v5_objects.dart';

abstract final class DatabaseSchemaV5 {
  static const String schemaMigrationsCreateStatement = '''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      checksum TEXT NOT NULL,
      applied_at INTEGER NOT NULL
    )
    ''';

  static const List<String> businessTableNames = <String>[
    'vaults',
    'secret_items',
    'note_items',
    'tags',
    'item_tags',
    'categories',
    'embedding_chunks',
    'model_registry',
    'model_catalog_entries',
    'download_tasks',
    'provider_configs',
    'sync_accounts',
    'app_settings',
    'chat_sessions',
    'chat_messages',
    'security_metadata',
  ];

  static const List<String> businessTableCreateStatements = <String>[
    '''
    CREATE TABLE IF NOT EXISTS vaults (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      is_default INTEGER NOT NULL DEFAULT 0
        CHECK (is_default IN (0, 1)),
      encryption_version INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS secret_items (
      id TEXT PRIMARY KEY,
      vault_id TEXT NOT NULL
        REFERENCES vaults(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      username_ciphertext BLOB,
      password_ciphertext BLOB,
      website_url_ciphertext BLOB,
      note_ciphertext BLOB,
      category_id TEXT
        REFERENCES categories(id) ON DELETE SET NULL,
      favorite INTEGER NOT NULL DEFAULT 0
        CHECK (favorite IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      last_accessed_at INTEGER,
      deleted_at INTEGER
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS note_items (
      id TEXT PRIMARY KEY,
      vault_id TEXT NOT NULL
        REFERENCES vaults(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      content_ciphertext BLOB NOT NULL,
      summary_ciphertext BLOB,
      category_id TEXT
        REFERENCES categories(id) ON DELETE SET NULL,
      favorite INTEGER NOT NULL DEFAULT 0
        CHECK (favorite IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS tags (
      id TEXT PRIMARY KEY,
      vault_id TEXT NOT NULL
        REFERENCES vaults(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS item_tags (
      item_id TEXT NOT NULL,
      item_type TEXT NOT NULL
        CHECK (item_type IN ('secret', 'note')),
      tag_id TEXT NOT NULL
        REFERENCES tags(id) ON DELETE CASCADE,
      PRIMARY KEY (item_id, item_type, tag_id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS categories (
      id TEXT PRIMARY KEY,
      vault_id TEXT NOT NULL
        REFERENCES vaults(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS embedding_chunks (
      id TEXT PRIMARY KEY,
      source_id TEXT NOT NULL,
      source_type TEXT NOT NULL
        CHECK (source_type IN ('secret', 'note')),
      chunk_index INTEGER NOT NULL,
      plaintext_hash TEXT NOT NULL,
      model_id TEXT NOT NULL
        REFERENCES model_registry(id) ON DELETE CASCADE,
      vector_blob BLOB,
      token_count INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS model_registry (
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
      integrity_status TEXT NOT NULL DEFAULT 'unknown'
        CHECK (integrity_status IN ('unknown', 'valid', 'corrupted')),
      enabled INTEGER NOT NULL DEFAULT 0
        CHECK (enabled IN (0, 1)),
      installed_at INTEGER
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS model_catalog_entries (
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
    CREATE TABLE IF NOT EXISTS download_tasks (
      id TEXT PRIMARY KEY,
      model_id TEXT NOT NULL,
      source_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK (
        status IN (
          'idle',
          'queued',
          'downloading',
          'paused',
          'completed',
          'failed'
        )
      ),
      total_bytes INTEGER,
      downloaded_bytes INTEGER,
      average_speed REAL,
      error_message TEXT,
      resumable INTEGER NOT NULL DEFAULT 1
        CHECK (resumable IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS provider_configs (
      id TEXT PRIMARY KEY,
      provider_type TEXT NOT NULL
        CHECK (provider_type IN ('openAiCompatible', 'ollama')),
      name TEXT NOT NULL,
      encrypted_config BLOB NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 0
        CHECK (enabled IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS sync_accounts (
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
    CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY,
      value_ciphertext BLOB NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS chat_sessions (
      id TEXT PRIMARY KEY,
      mode TEXT NOT NULL
        CHECK (mode IN ('privateQa', 'freeChat')),
      title TEXT NOT NULL,
      allow_private_context INTEGER NOT NULL DEFAULT 0
        CHECK (allow_private_context IN (0, 1)),
      last_model_id TEXT,
      archived INTEGER NOT NULL DEFAULT 0
        CHECK (archived IN (0, 1)),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS chat_messages (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL
        REFERENCES chat_sessions(id) ON DELETE CASCADE,
      role TEXT NOT NULL
        CHECK (role IN ('user', 'assistant', 'system')),
      content TEXT NOT NULL,
      status TEXT NOT NULL
        CHECK (status IN ('loading', 'completed', 'failed')),
      used_private_context INTEGER NOT NULL DEFAULT 0
        CHECK (used_private_context IN (0, 1)),
      auto_retrieved_context_summary TEXT,
      manual_context_item_ids_json TEXT,
      related_source_ids_json TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS security_metadata (
      key_id TEXT PRIMARY KEY,
      source_schema_version INTEGER NOT NULL,
      field_envelope_version INTEGER NOT NULL,
      migration_state TEXT NOT NULL,
      migrated_at INTEGER NOT NULL
    )
    ''',
  ];

  static const List<String> createStatements = <String>[
    ...businessTableCreateStatements,
    schemaMigrationsCreateStatement,
    ...DatabaseSchemaV5Objects.createStatements,
  ];
}
