abstract final class DatabaseSchemaV5Objects {
  static const List<String> createStatements = <String>[
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_vaults_single_default
    ON vaults(is_default)
    WHERE is_default = 1
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_categories_vault_name_nocase
    ON categories(vault_id, name COLLATE NOCASE)
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_tags_vault_name_nocase
    ON tags(vault_id, name COLLATE NOCASE)
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_embedding_chunks_source_model_chunk
    ON embedding_chunks(source_type, source_id, model_id, chunk_index)
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_provider_configs_enabled_type
    ON provider_configs(provider_type)
    WHERE enabled = 1
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_secret_items_active_vault_updated
    ON secret_items(vault_id, favorite DESC, updated_at DESC, id)
    WHERE deleted_at IS NULL
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_secret_items_vault
    ON secret_items(vault_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_secret_items_category
    ON secret_items(category_id)
    WHERE category_id IS NOT NULL
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_note_items_active_vault_updated
    ON note_items(vault_id, favorite DESC, updated_at DESC, id)
    WHERE deleted_at IS NULL
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_note_items_vault
    ON note_items(vault_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_note_items_category
    ON note_items(category_id)
    WHERE category_id IS NOT NULL
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_item_tags_tag_item
    ON item_tags(tag_id, item_type, item_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_embedding_chunks_source
    ON embedding_chunks(source_type, source_id, model_id, chunk_index)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_embedding_chunks_model
    ON embedding_chunks(model_id, source_type, source_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_download_tasks_model_updated
    ON download_tasks(model_id, updated_at DESC, id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_download_tasks_model_source_updated
    ON download_tasks(model_id, source_id, updated_at DESC, id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_download_tasks_updated
    ON download_tasks(updated_at DESC, id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_model_registry_installed
    ON model_registry(installed_at DESC, id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_provider_configs_enabled_updated
    ON provider_configs(enabled, updated_at DESC, id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_provider_configs_updated
    ON provider_configs(updated_at DESC, id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_chat_sessions_updated
    ON chat_sessions(updated_at DESC, id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_chat_messages_session_created
    ON chat_messages(session_id, created_at ASC, id)
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_secret_category_owner_insert
    BEFORE INSERT ON secret_items
    WHEN NEW.category_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM categories
        WHERE id = NEW.category_id AND vault_id = NEW.vault_id
      )
    BEGIN
      SELECT RAISE(ABORT, 'secret_category_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_secret_category_owner_update
    BEFORE UPDATE OF vault_id, category_id ON secret_items
    WHEN NEW.category_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM categories
        WHERE id = NEW.category_id AND vault_id = NEW.vault_id
      )
    BEGIN
      SELECT RAISE(ABORT, 'secret_category_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_note_category_owner_insert
    BEFORE INSERT ON note_items
    WHEN NEW.category_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM categories
        WHERE id = NEW.category_id AND vault_id = NEW.vault_id
      )
    BEGIN
      SELECT RAISE(ABORT, 'note_category_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_note_category_owner_update
    BEFORE UPDATE OF vault_id, category_id ON note_items
    WHEN NEW.category_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM categories
        WHERE id = NEW.category_id AND vault_id = NEW.vault_id
      )
    BEGIN
      SELECT RAISE(ABORT, 'note_category_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_item_tags_owner_insert
    BEFORE INSERT ON item_tags
    WHEN (
      NEW.item_type = 'secret'
      AND NOT EXISTS (
        SELECT 1
        FROM secret_items item
        INNER JOIN tags tag ON tag.id = NEW.tag_id
        WHERE item.id = NEW.item_id
          AND item.deleted_at IS NULL
          AND item.vault_id = tag.vault_id
      )
    ) OR (
      NEW.item_type = 'note'
      AND NOT EXISTS (
        SELECT 1
        FROM note_items item
        INNER JOIN tags tag ON tag.id = NEW.tag_id
        WHERE item.id = NEW.item_id
          AND item.deleted_at IS NULL
          AND item.vault_id = tag.vault_id
      )
    )
    BEGIN
      SELECT RAISE(ABORT, 'item_tag_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_item_tags_owner_update
    BEFORE UPDATE OF item_id, item_type, tag_id ON item_tags
    WHEN (
      NEW.item_type = 'secret'
      AND NOT EXISTS (
        SELECT 1
        FROM secret_items item
        INNER JOIN tags tag ON tag.id = NEW.tag_id
        WHERE item.id = NEW.item_id
          AND item.deleted_at IS NULL
          AND item.vault_id = tag.vault_id
      )
    ) OR (
      NEW.item_type = 'note'
      AND NOT EXISTS (
        SELECT 1
        FROM note_items item
        INNER JOIN tags tag ON tag.id = NEW.tag_id
        WHERE item.id = NEW.item_id
          AND item.deleted_at IS NULL
          AND item.vault_id = tag.vault_id
      )
    )
    BEGIN
      SELECT RAISE(ABORT, 'item_tag_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_embedding_chunks_source_insert
    BEFORE INSERT ON embedding_chunks
    WHEN (
      NEW.source_type = 'secret'
      AND NOT EXISTS (
        SELECT 1 FROM secret_items
        WHERE id = NEW.source_id AND deleted_at IS NULL
      )
    ) OR (
      NEW.source_type = 'note'
      AND NOT EXISTS (
        SELECT 1 FROM note_items
        WHERE id = NEW.source_id AND deleted_at IS NULL
      )
    )
    BEGIN
      SELECT RAISE(ABORT, 'embedding_source_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_embedding_chunks_source_update
    BEFORE UPDATE OF source_id, source_type ON embedding_chunks
    WHEN (
      NEW.source_type = 'secret'
      AND NOT EXISTS (
        SELECT 1 FROM secret_items
        WHERE id = NEW.source_id AND deleted_at IS NULL
      )
    ) OR (
      NEW.source_type = 'note'
      AND NOT EXISTS (
        SELECT 1 FROM note_items
        WHERE id = NEW.source_id AND deleted_at IS NULL
      )
    )
    BEGIN
      SELECT RAISE(ABORT, 'embedding_source_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_categories_vault_owner_update
    BEFORE UPDATE OF vault_id ON categories
    WHEN EXISTS (
      SELECT 1 FROM secret_items
      WHERE category_id = OLD.id AND vault_id != NEW.vault_id
    ) OR EXISTS (
      SELECT 1 FROM note_items
      WHERE category_id = OLD.id AND vault_id != NEW.vault_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'category_vault_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_tags_vault_owner_update
    BEFORE UPDATE OF vault_id ON tags
    WHEN EXISTS (
      SELECT 1
      FROM item_tags link
      INNER JOIN secret_items item
        ON link.item_type = 'secret' AND item.id = link.item_id
      WHERE link.tag_id = OLD.id AND item.vault_id != NEW.vault_id
    ) OR EXISTS (
      SELECT 1
      FROM item_tags link
      INNER JOIN note_items item
        ON link.item_type = 'note' AND item.id = link.item_id
      WHERE link.tag_id = OLD.id AND item.vault_id != NEW.vault_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'tag_vault_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_secret_vault_tag_owner_update
    BEFORE UPDATE OF vault_id ON secret_items
    WHEN EXISTS (
      SELECT 1
      FROM item_tags link
      INNER JOIN tags tag ON tag.id = link.tag_id
      WHERE link.item_type = 'secret'
        AND link.item_id = OLD.id
        AND tag.vault_id != NEW.vault_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'secret_tag_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_note_vault_tag_owner_update
    BEFORE UPDATE OF vault_id ON note_items
    WHEN EXISTS (
      SELECT 1
      FROM item_tags link
      INNER JOIN tags tag ON tag.id = link.tag_id
      WHERE link.item_type = 'note'
        AND link.item_id = OLD.id
        AND tag.vault_id != NEW.vault_id
    )
    BEGIN
      SELECT RAISE(ABORT, 'note_tag_owner_invalid');
    END
    ''',
  ];
}
