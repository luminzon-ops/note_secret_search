import 'package:note_secret_search/core/storage/database/database_schema_v6_objects.dart';

abstract final class DatabaseSchemaV6 {
  static const String indexSetsTable = 'embedding_index_sets';

  static const String indexSetsCreateStatement = '''
    CREATE TABLE IF NOT EXISTS embedding_index_sets (
      id TEXT PRIMARY KEY,
      source_type TEXT NOT NULL
        CHECK (source_type IN ('secret', 'note')),
      source_id TEXT NOT NULL,
      vault_id TEXT NOT NULL
        REFERENCES vaults(id) ON DELETE CASCADE,
      model_id TEXT NOT NULL
        REFERENCES model_registry(id) ON DELETE CASCADE,
      model_revision_hash TEXT NOT NULL
        CHECK (
          length(model_revision_hash) = 64
          AND model_revision_hash NOT GLOB '*[^0-9a-f]*'
        ),
      source_updated_at INTEGER NOT NULL,
      source_fingerprint BLOB NOT NULL
        CHECK (length(source_fingerprint) = 32),
      fingerprint_key_id TEXT NOT NULL
        CHECK (length(fingerprint_key_id) > 0),
      fingerprint_version INTEGER NOT NULL
        CHECK (fingerprint_version >= 1),
      index_config_version INTEGER NOT NULL
        CHECK (index_config_version >= 1),
      index_config_epoch INTEGER NOT NULL
        CHECK (index_config_epoch >= 0),
      index_config_hash TEXT NOT NULL
        CHECK (
          length(index_config_hash) = 64
          AND index_config_hash NOT GLOB '*[^0-9a-f]*'
        ),
      chunk_schema_version INTEGER NOT NULL
        CHECK (chunk_schema_version >= 1),
      vector_format_version INTEGER NOT NULL
        CHECK (vector_format_version >= 1),
      vector_dimension INTEGER NOT NULL
        CHECK (vector_dimension >= 0),
      chunk_count INTEGER NOT NULL
        CHECK (chunk_count >= 0),
      created_at INTEGER NOT NULL,
      UNIQUE (source_type, source_id, model_id),
      CHECK (
        (chunk_count = 0 AND vector_dimension = 0)
        OR (chunk_count > 0 AND vector_dimension > 0)
      )
    )
    ''';

  static const String chunksCreateStatement = '''
    CREATE TABLE IF NOT EXISTS embedding_chunks (
      id TEXT PRIMARY KEY,
      index_set_id TEXT NOT NULL
        REFERENCES embedding_index_sets(id) ON DELETE CASCADE,
      source_field TEXT NOT NULL CHECK (
        source_field IN (
          'secret.title',
          'secret.username',
          'secret.password',
          'secret.website_url',
          'secret.note',
          'secret.tags',
          'note.title',
          'note.summary',
          'note.body',
          'note.tags'
        )
      ),
      field_chunk_index INTEGER NOT NULL
        CHECK (field_chunk_index >= 0),
      chunk_fingerprint BLOB NOT NULL
        CHECK (length(chunk_fingerprint) = 32),
      vector_blob BLOB NOT NULL,
      token_count INTEGER
        CHECK (token_count IS NULL OR token_count >= 0),
      created_at INTEGER NOT NULL,
      UNIQUE (index_set_id, source_field, field_chunk_index)
    )
    ''';

  static const List<String> createStatements = <String>[
    indexSetsCreateStatement,
    chunksCreateStatement,
    ...DatabaseSchemaV6Objects.createStatements,
  ];
}
