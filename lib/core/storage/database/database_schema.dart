abstract final class DatabaseSchema {
  static const String vaults = 'vaults';
  static const String secretItems = 'secret_items';
  static const String noteItems = 'note_items';
  static const String tags = 'tags';
  static const String itemTags = 'item_tags';
  static const String categories = 'categories';
  static const String embeddingChunks = 'embedding_chunks';
  static const String modelRegistry = 'model_registry';
  static const String modelCatalogEntries = 'model_catalog_entries';
  static const String downloadTasks = 'download_tasks';
  static const String providerConfigs = 'provider_configs';
  static const String syncAccounts = 'sync_accounts';
  static const String appSettings = 'app_settings';
  static const String chatSessions = 'chat_sessions';
  static const String chatMessages = 'chat_messages';

  static const List<String> createStatements = [
    '''
    CREATE TABLE IF NOT EXISTS vaults (
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
    CREATE TABLE IF NOT EXISTS secret_items (
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
    CREATE TABLE IF NOT EXISTS note_items (
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
    CREATE TABLE IF NOT EXISTS tags (
      id TEXT PRIMARY KEY,
      vault_id TEXT NOT NULL,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS item_tags (
      item_id TEXT NOT NULL,
      item_type TEXT NOT NULL,
      tag_id TEXT NOT NULL,
      PRIMARY KEY (item_id, item_type, tag_id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS categories (
      id TEXT PRIMARY KEY,
      vault_id TEXT NOT NULL,
      name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS embedding_chunks (
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
      integrity_status TEXT NOT NULL DEFAULT 'unknown',
      enabled INTEGER NOT NULL DEFAULT 0,
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
    CREATE TABLE IF NOT EXISTS provider_configs (
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
    ...chatPersistenceStatements,
  ];

  static const List<String> chatPersistenceStatements = [
    '''
    CREATE TABLE IF NOT EXISTS chat_sessions (
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
    CREATE TABLE IF NOT EXISTS chat_messages (
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
}
