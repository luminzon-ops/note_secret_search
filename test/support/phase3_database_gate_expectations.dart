const phase3ExpectedMigrationName = 'database_schema_v5';
const phase3ExpectedMigrationChecksum =
    '72961f4e65faded09a0b1afdfdadee2b'
    '3fb4cf0bb016a4519692adfdb0adeca8';
const phase3ExpectedSchemaFingerprint =
    '788a6b784f6c1e31db0382fa84c663a5'
    'dcd00e6a99dfc4913bb0ef551a311c0c';

const phase3ExpectedPlaintext = <String, String?>{
  'secret-1.username_ciphertext': 'alice',
  'secret-1.password_ciphertext': 'correct horse battery staple',
  'secret-1.website_url_ciphertext': 'https://example.test/login',
  'secret-1.note_ciphertext': 'primary secret note',
  'secret-deleted.username_ciphertext': null,
  'secret-deleted.password_ciphertext': 'deleted password',
  'secret-deleted.website_url_ciphertext': '',
  'secret-deleted.note_ciphertext': null,
  'note-1.content_ciphertext': '完整的旧版笔记正文',
  'note-1.summary_ciphertext': '旧版摘要',
  'note-deleted.content_ciphertext': 'soft deleted note',
  'note-deleted.summary_ciphertext': null,
  'provider-1.encrypted_config':
      '{"endpoint":"https://api.example.test","apiKey":"provider-secret"}',
  'sync-1.encrypted_config':
      '{"server":"https://sync.example.test","token":"sync-secret"}',
  'search.scope.value_ciphertext': 'secret,note',
};

class Phase3QueryPlanCase {
  const Phase3QueryPlanCase(this.sql, this.arguments, this.indexName);

  final String sql;
  final List<Object?> arguments;
  final String indexName;
}

const phase3QueryPlanCases = <Phase3QueryPlanCase>[
  Phase3QueryPlanCase(
    'SELECT * FROM secret_items WHERE vault_id = ? AND deleted_at IS NULL '
        'ORDER BY favorite DESC, updated_at DESC, id ASC',
    <Object?>['vault-1'],
    'idx_secret_items_active_vault_updated',
  ),
  Phase3QueryPlanCase(
    'SELECT * FROM note_items WHERE vault_id = ? AND deleted_at IS NULL '
        'ORDER BY favorite DESC, updated_at DESC, id ASC',
    <Object?>['vault-1'],
    'idx_note_items_active_vault_updated',
  ),
  Phase3QueryPlanCase(
    'SELECT item_id, item_type FROM item_tags WHERE tag_id = ? '
        'ORDER BY item_type ASC, item_id ASC',
    <Object?>['tag-1'],
    'idx_item_tags_tag_item',
  ),
  Phase3QueryPlanCase(
    'SELECT * FROM model_registry ORDER BY installed_at DESC, id ASC',
    <Object?>[],
    'idx_model_registry_installed',
  ),
];

const phase3V5Tables = <String>{
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
  'schema_migrations',
};

const phase3V5Indexes = <String>{
  'uq_vaults_single_default',
  'uq_categories_vault_name_nocase',
  'uq_tags_vault_name_nocase',
  'uq_embedding_chunks_source_model_chunk',
  'uq_provider_configs_enabled_type',
  'idx_secret_items_active_vault_updated',
  'idx_secret_items_vault',
  'idx_secret_items_category',
  'idx_note_items_active_vault_updated',
  'idx_note_items_vault',
  'idx_note_items_category',
  'idx_item_tags_tag_item',
  'idx_embedding_chunks_source',
  'idx_embedding_chunks_model',
  'idx_download_tasks_model_updated',
  'idx_download_tasks_model_source_updated',
  'idx_download_tasks_updated',
  'idx_model_registry_installed',
  'idx_provider_configs_enabled_updated',
  'idx_provider_configs_updated',
  'idx_chat_sessions_updated',
  'idx_chat_messages_session_created',
};

const phase3V5Triggers = <String>{
  'trg_secret_category_owner_insert',
  'trg_secret_category_owner_update',
  'trg_note_category_owner_insert',
  'trg_note_category_owner_update',
  'trg_item_tags_owner_insert',
  'trg_item_tags_owner_update',
  'trg_embedding_chunks_source_insert',
  'trg_embedding_chunks_source_update',
  'trg_categories_vault_owner_update',
  'trg_tags_vault_owner_update',
  'trg_secret_vault_tag_owner_update',
  'trg_note_vault_tag_owner_update',
};
