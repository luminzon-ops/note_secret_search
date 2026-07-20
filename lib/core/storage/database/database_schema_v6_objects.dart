abstract final class DatabaseSchemaV6Objects {
  static const List<String> createStatements = <String>[
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS uq_embedding_index_sets_source_model
    ON embedding_index_sets(source_type, source_id, model_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_embedding_index_sets_scope
    ON embedding_index_sets(vault_id, model_id, source_type, source_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_embedding_chunks_set_field
    ON embedding_chunks(index_set_id, source_field, field_chunk_index)
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_embedding_index_sets_source_insert
    BEFORE INSERT ON embedding_index_sets
    WHEN (
      NEW.source_type = 'secret'
      AND NOT EXISTS (
        SELECT 1 FROM secret_items
        WHERE id = NEW.source_id
          AND vault_id = NEW.vault_id
          AND deleted_at IS NULL
      )
    ) OR (
      NEW.source_type = 'note'
      AND NOT EXISTS (
        SELECT 1 FROM note_items
        WHERE id = NEW.source_id
          AND vault_id = NEW.vault_id
          AND deleted_at IS NULL
      )
    ) OR NOT EXISTS (
      SELECT 1 FROM model_registry
      WHERE id = NEW.model_id AND type = 'embedding'
    )
    BEGIN
      SELECT RAISE(ABORT, 'embedding_index_set_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_embedding_index_sets_source_update
    BEFORE UPDATE OF source_type, source_id, vault_id, model_id
      ON embedding_index_sets
    WHEN (
      NEW.source_type = 'secret'
      AND NOT EXISTS (
        SELECT 1 FROM secret_items
        WHERE id = NEW.source_id
          AND vault_id = NEW.vault_id
          AND deleted_at IS NULL
      )
    ) OR (
      NEW.source_type = 'note'
      AND NOT EXISTS (
        SELECT 1 FROM note_items
        WHERE id = NEW.source_id
          AND vault_id = NEW.vault_id
          AND deleted_at IS NULL
      )
    ) OR NOT EXISTS (
      SELECT 1 FROM model_registry
      WHERE id = NEW.model_id AND type = 'embedding'
    )
    BEGIN
      SELECT RAISE(ABORT, 'embedding_index_set_owner_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_embedding_chunks_metadata_insert
    BEFORE INSERT ON embedding_chunks
    WHEN NOT EXISTS (
      SELECT 1
      FROM embedding_index_sets index_set
      WHERE index_set.id = NEW.index_set_id
        AND index_set.chunk_count > 0
        AND length(NEW.vector_blob) = index_set.vector_dimension * 4
        AND (
          (index_set.source_type = 'secret' AND NEW.source_field IN (
            'secret.title', 'secret.username', 'secret.website_url',
            'secret.note', 'secret.tags'
          ))
          OR (index_set.source_type = 'note' AND NEW.source_field IN (
            'note.title', 'note.summary', 'note.body', 'note.tags'
          ))
        )
    )
    BEGIN
      SELECT RAISE(ABORT, 'embedding_chunk_metadata_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_embedding_chunks_metadata_update
    BEFORE UPDATE OF index_set_id, source_field, field_chunk_index, vector_blob
      ON embedding_chunks
    WHEN NOT EXISTS (
      SELECT 1
      FROM embedding_index_sets index_set
      WHERE index_set.id = NEW.index_set_id
        AND index_set.chunk_count > 0
        AND length(NEW.vector_blob) = index_set.vector_dimension * 4
        AND (
          (index_set.source_type = 'secret' AND NEW.source_field IN (
            'secret.title', 'secret.username', 'secret.website_url',
            'secret.note', 'secret.tags'
          ))
          OR (index_set.source_type = 'note' AND NEW.source_field IN (
            'note.title', 'note.summary', 'note.body', 'note.tags'
          ))
        )
    )
    BEGIN
      SELECT RAISE(ABORT, 'embedding_chunk_metadata_invalid');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_secret_embedding_index_invalidate
    AFTER UPDATE OF vault_id, title, username_ciphertext,
      website_url_ciphertext, note_ciphertext, deleted_at ON secret_items
    WHEN OLD.vault_id IS NOT NEW.vault_id
      OR OLD.title IS NOT NEW.title
      OR OLD.username_ciphertext IS NOT NEW.username_ciphertext
      OR OLD.website_url_ciphertext IS NOT NEW.website_url_ciphertext
      OR OLD.note_ciphertext IS NOT NEW.note_ciphertext
      OR OLD.deleted_at IS NOT NEW.deleted_at
    BEGIN
      DELETE FROM embedding_index_sets
      WHERE source_type = 'secret' AND source_id = OLD.id;
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_note_embedding_index_invalidate
    AFTER UPDATE OF vault_id, title, content_ciphertext,
      summary_ciphertext, deleted_at ON note_items
    WHEN OLD.vault_id IS NOT NEW.vault_id
      OR OLD.title IS NOT NEW.title
      OR OLD.content_ciphertext IS NOT NEW.content_ciphertext
      OR OLD.summary_ciphertext IS NOT NEW.summary_ciphertext
      OR OLD.deleted_at IS NOT NEW.deleted_at
    BEGIN
      DELETE FROM embedding_index_sets
      WHERE source_type = 'note' AND source_id = OLD.id;
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_item_tags_embedding_index_invalidate
    AFTER INSERT ON item_tags
    BEGIN
      DELETE FROM embedding_index_sets
      WHERE source_type = NEW.item_type AND source_id = NEW.item_id;
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_item_tags_embedding_index_delete
    AFTER DELETE ON item_tags
    BEGIN
      DELETE FROM embedding_index_sets
      WHERE source_type = OLD.item_type AND source_id = OLD.item_id;
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_item_tags_embedding_index_update
    AFTER UPDATE OF item_id, item_type, tag_id ON item_tags
    BEGIN
      DELETE FROM embedding_index_sets
      WHERE (source_type = OLD.item_type AND source_id = OLD.item_id)
        OR (source_type = NEW.item_type AND source_id = NEW.item_id);
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_tags_embedding_index_invalidate
    AFTER UPDATE OF name, vault_id ON tags
    BEGIN
      DELETE FROM embedding_index_sets
      WHERE (source_type = 'secret' AND source_id IN (
        SELECT item_id FROM item_tags
        WHERE item_type = 'secret' AND tag_id = OLD.id
      )) OR (source_type = 'note' AND source_id IN (
        SELECT item_id FROM item_tags
        WHERE item_type = 'note' AND tag_id = OLD.id
      ));
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_model_embedding_index_invalidate
    AFTER UPDATE OF type, provider, version, quantization, checksum,
      artifact_paths_json, integrity_status ON model_registry
    WHEN OLD.type IS NOT NEW.type
      OR OLD.provider IS NOT NEW.provider
      OR OLD.version IS NOT NEW.version
      OR OLD.quantization IS NOT NEW.quantization
      OR OLD.checksum IS NOT NEW.checksum
      OR OLD.artifact_paths_json IS NOT NEW.artifact_paths_json
      OR OLD.integrity_status IS NOT NEW.integrity_status
    BEGIN
      DELETE FROM embedding_index_sets WHERE model_id = OLD.id;
    END
    ''',
  ];
}
