import 'package:note_secret_search/core/storage/database/database_schema_v5.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

class DatabaseSchemaV4InventoryException implements Exception {
  const DatabaseSchemaV4InventoryException();
}

abstract final class DatabaseSchemaV4Inventory {
  static Future<void> validate(DatabaseExecutor database) async {
    final tables = {
      for (final row in await database.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        '''))
        row['name']! as String,
    };
    if (tables.length != DatabaseSchemaV5.businessTableNames.length ||
        !tables.containsAll(DatabaseSchemaV5.businessTableNames)) {
      throw const DatabaseSchemaV4InventoryException();
    }

    for (final entry in tableColumns.entries) {
      final rows = await database.rawQuery(
        'PRAGMA table_info(${_quoteIdentifier(entry.key)})',
      );
      final actualColumns = {for (final row in rows) row['name']! as String};
      final expectedColumns = entry.value.toSet();
      final allowedWithoutIntegrity = entry.key == 'model_registry'
          ? ({...expectedColumns}..remove('integrity_status'))
          : expectedColumns;
      if (!_sameSet(actualColumns, expectedColumns) &&
          !_sameSet(actualColumns, allowedWithoutIntegrity)) {
        throw const DatabaseSchemaV4InventoryException();
      }
      for (final row in rows) {
        _validateColumn(entry.key, row);
      }
    }

    final schemaObjects = await database.rawQuery('''
      SELECT 1
      FROM sqlite_master
      WHERE type IN ('index', 'trigger')
        AND name NOT LIKE 'sqlite_%'
      LIMIT 1
      ''');
    if (schemaObjects.isNotEmpty) {
      throw const DatabaseSchemaV4InventoryException();
    }
  }

  static void _validateColumn(String table, Map<String, Object?> row) {
    final name = row['name']! as String;
    final expectedType = _columnType(table, name);
    final primaryKeyPosition = _primaryKeyPosition(table, name);
    final expectedNotNull = table == 'item_tags' || primaryKeyPosition == 0
        ? (_nullableColumns[table]?.contains(name) ?? false ? 0 : 1)
        : 0;
    final expectedDefault = _defaultValues[table]?[name];
    if (row['type'].toString().toUpperCase() != expectedType ||
        row['notnull'] != expectedNotNull ||
        row['dflt_value']?.toString() != expectedDefault ||
        row['pk'] != primaryKeyPosition) {
      throw const DatabaseSchemaV4InventoryException();
    }
  }

  static String _columnType(String table, String column) {
    if (_blobColumns[table]?.contains(column) ?? false) {
      return 'BLOB';
    }
    if (_integerColumns[table]?.contains(column) ?? false) {
      return 'INTEGER';
    }
    if (table == 'download_tasks' && column == 'average_speed') {
      return 'REAL';
    }
    return 'TEXT';
  }

  static int _primaryKeyPosition(String table, String column) {
    final primaryKey = table == 'item_tags'
        ? const <String>['item_id', 'item_type', 'tag_id']
        : table == 'app_settings'
        ? const <String>['key']
        : table == 'security_metadata'
        ? const <String>['key_id']
        : tableColumns[table]!.contains('id')
        ? const <String>['id']
        : const <String>[];
    final index = primaryKey.indexOf(column);
    return index < 0 ? 0 : index + 1;
  }

  static const Map<String, List<String>> tableColumns = <String, List<String>>{
    'vaults': <String>[
      'id',
      'name',
      'description',
      'is_default',
      'encryption_version',
      'created_at',
      'updated_at',
    ],
    'secret_items': <String>[
      'id',
      'vault_id',
      'title',
      'username_ciphertext',
      'password_ciphertext',
      'website_url_ciphertext',
      'note_ciphertext',
      'category_id',
      'favorite',
      'created_at',
      'updated_at',
      'last_accessed_at',
      'deleted_at',
    ],
    'note_items': <String>[
      'id',
      'vault_id',
      'title',
      'content_ciphertext',
      'summary_ciphertext',
      'category_id',
      'favorite',
      'created_at',
      'updated_at',
      'deleted_at',
    ],
    'tags': <String>['id', 'vault_id', 'name', 'created_at'],
    'item_tags': <String>['item_id', 'item_type', 'tag_id'],
    'categories': <String>['id', 'vault_id', 'name', 'sort_order'],
    'embedding_chunks': <String>[
      'id',
      'source_id',
      'source_type',
      'chunk_index',
      'plaintext_hash',
      'model_id',
      'vector_blob',
      'token_count',
      'created_at',
      'updated_at',
    ],
    'model_registry': <String>[
      'id',
      'type',
      'provider',
      'name',
      'version',
      'size_bytes',
      'quantization',
      'min_ram_mb',
      'recommended_tier',
      'local_path',
      'artifact_paths_json',
      'checksum',
      'integrity_status',
      'enabled',
      'installed_at',
    ],
    'model_catalog_entries': <String>[
      'id',
      'type',
      'tier',
      'display_name',
      'description',
      'quantization',
      'size_bytes',
      'min_ram_mb',
      'recommended_tier',
      'speed_hint',
      'quality_hint',
      'license',
      'release_date',
      'source_list_json',
      'checksum',
      'signature',
      'updated_at',
    ],
    'download_tasks': <String>[
      'id',
      'model_id',
      'source_id',
      'status',
      'total_bytes',
      'downloaded_bytes',
      'average_speed',
      'error_message',
      'resumable',
      'created_at',
      'updated_at',
    ],
    'provider_configs': <String>[
      'id',
      'provider_type',
      'name',
      'encrypted_config',
      'enabled',
      'created_at',
      'updated_at',
    ],
    'sync_accounts': <String>[
      'id',
      'provider_type',
      'encrypted_config',
      'last_sync_at',
      'status',
      'created_at',
      'updated_at',
    ],
    'app_settings': <String>['key', 'value_ciphertext'],
    'chat_sessions': <String>[
      'id',
      'mode',
      'title',
      'allow_private_context',
      'last_model_id',
      'archived',
      'created_at',
      'updated_at',
    ],
    'chat_messages': <String>[
      'id',
      'session_id',
      'role',
      'content',
      'status',
      'used_private_context',
      'auto_retrieved_context_summary',
      'manual_context_item_ids_json',
      'related_source_ids_json',
      'created_at',
    ],
    'security_metadata': <String>[
      'key_id',
      'source_schema_version',
      'field_envelope_version',
      'migration_state',
      'migrated_at',
    ],
  };
}

const _blobColumns = <String, Set<String>>{
  'secret_items': <String>{
    'username_ciphertext',
    'password_ciphertext',
    'website_url_ciphertext',
    'note_ciphertext',
  },
  'note_items': <String>{'content_ciphertext', 'summary_ciphertext'},
  'embedding_chunks': <String>{'vector_blob'},
  'provider_configs': <String>{'encrypted_config'},
  'sync_accounts': <String>{'encrypted_config'},
  'app_settings': <String>{'value_ciphertext'},
};

const _integerColumns = <String, Set<String>>{
  'vaults': <String>{
    'is_default',
    'encryption_version',
    'created_at',
    'updated_at',
  },
  'secret_items': <String>{
    'favorite',
    'created_at',
    'updated_at',
    'last_accessed_at',
    'deleted_at',
  },
  'note_items': <String>{'favorite', 'created_at', 'updated_at', 'deleted_at'},
  'tags': <String>{'created_at'},
  'categories': <String>{'sort_order'},
  'embedding_chunks': <String>{
    'chunk_index',
    'token_count',
    'created_at',
    'updated_at',
  },
  'model_registry': <String>{
    'size_bytes',
    'min_ram_mb',
    'enabled',
    'installed_at',
  },
  'model_catalog_entries': <String>{'size_bytes', 'min_ram_mb', 'updated_at'},
  'download_tasks': <String>{
    'total_bytes',
    'downloaded_bytes',
    'resumable',
    'created_at',
    'updated_at',
  },
  'provider_configs': <String>{'enabled', 'created_at', 'updated_at'},
  'sync_accounts': <String>{'last_sync_at', 'created_at', 'updated_at'},
  'chat_sessions': <String>{
    'allow_private_context',
    'archived',
    'created_at',
    'updated_at',
  },
  'chat_messages': <String>{'used_private_context', 'created_at'},
  'security_metadata': <String>{
    'source_schema_version',
    'field_envelope_version',
    'migrated_at',
  },
};

const _nullableColumns = <String, Set<String>>{
  'vaults': <String>{'description'},
  'secret_items': <String>{
    'username_ciphertext',
    'password_ciphertext',
    'website_url_ciphertext',
    'note_ciphertext',
    'category_id',
    'last_accessed_at',
    'deleted_at',
  },
  'note_items': <String>{'summary_ciphertext', 'category_id', 'deleted_at'},
  'embedding_chunks': <String>{'vector_blob', 'token_count'},
  'model_registry': <String>{
    'version',
    'size_bytes',
    'quantization',
    'min_ram_mb',
    'recommended_tier',
    'local_path',
    'artifact_paths_json',
    'checksum',
    'installed_at',
  },
  'model_catalog_entries': <String>{
    'description',
    'quantization',
    'size_bytes',
    'min_ram_mb',
    'recommended_tier',
    'speed_hint',
    'quality_hint',
    'license',
    'release_date',
    'source_list_json',
    'checksum',
    'signature',
  },
  'download_tasks': <String>{
    'total_bytes',
    'downloaded_bytes',
    'average_speed',
    'error_message',
  },
  'sync_accounts': <String>{'last_sync_at'},
  'chat_sessions': <String>{'last_model_id'},
  'chat_messages': <String>{
    'auto_retrieved_context_summary',
    'manual_context_item_ids_json',
    'related_source_ids_json',
  },
};

const _defaultValues = <String, Map<String, String>>{
  'vaults': <String, String>{'is_default': '0', 'encryption_version': '1'},
  'secret_items': <String, String>{'favorite': '0'},
  'note_items': <String, String>{'favorite': '0'},
  'categories': <String, String>{'sort_order': '0'},
  'model_registry': <String, String>{
    'integrity_status': "'unknown'",
    'enabled': '0',
  },
  'download_tasks': <String, String>{'resumable': '1'},
  'provider_configs': <String, String>{'enabled': '0'},
  'chat_sessions': <String, String>{
    'allow_private_context': '0',
    'archived': '0',
  },
  'chat_messages': <String, String>{'used_private_context': '0'},
};

bool _sameSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';
