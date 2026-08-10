import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

abstract final class LegacyMigrationSchema {
  static const preservedTables = <String>[
    DatabaseSchema.vaults,
    DatabaseSchema.categories,
    DatabaseSchema.tags,
    DatabaseSchema.secretItems,
    DatabaseSchema.noteItems,
    DatabaseSchema.itemTags,
    DatabaseSchema.modelRegistry,
    DatabaseSchema.providerConfigs,
    DatabaseSchema.syncAccounts,
    DatabaseSchema.appSettings,
    DatabaseSchema.chatSessions,
    DatabaseSchema.chatMessages,
  ];

  static const primaryKeyColumns = <String, List<String>>{
    DatabaseSchema.vaults: ['id'],
    DatabaseSchema.categories: ['id'],
    DatabaseSchema.tags: ['id'],
    DatabaseSchema.secretItems: ['id'],
    DatabaseSchema.noteItems: ['id'],
    DatabaseSchema.itemTags: ['item_id', 'item_type', 'tag_id'],
    DatabaseSchema.modelRegistry: ['id'],
    DatabaseSchema.providerConfigs: ['id'],
    DatabaseSchema.syncAccounts: ['id'],
    DatabaseSchema.appSettings: ['key'],
    DatabaseSchema.chatSessions: ['id'],
    DatabaseSchema.chatMessages: ['id'],
  };

  static const encryptedColumns = <String, Set<String>>{
    DatabaseSchema.secretItems: {
      'username_ciphertext',
      'password_ciphertext',
      'website_url_ciphertext',
      'note_ciphertext',
    },
    DatabaseSchema.noteItems: {'content_ciphertext', 'summary_ciphertext'},
    DatabaseSchema.providerConfigs: {'encrypted_config'},
    DatabaseSchema.syncAccounts: {'encrypted_config'},
    DatabaseSchema.appSettings: {'value_ciphertext'},
  };

  static const _requiredColumns = <String, Map<String, String>>{
    DatabaseSchema.vaults: {
      'id': 'TEXT',
      'name': 'TEXT',
      'description': 'TEXT',
      'is_default': 'INTEGER',
      'encryption_version': 'INTEGER',
      'created_at': 'INTEGER',
      'updated_at': 'INTEGER',
    },
    DatabaseSchema.categories: {
      'id': 'TEXT',
      'vault_id': 'TEXT',
      'name': 'TEXT',
      'sort_order': 'INTEGER',
    },
    DatabaseSchema.tags: {
      'id': 'TEXT',
      'vault_id': 'TEXT',
      'name': 'TEXT',
      'created_at': 'INTEGER',
    },
    DatabaseSchema.secretItems: {
      'id': 'TEXT',
      'vault_id': 'TEXT',
      'title': 'TEXT',
      'username_ciphertext': 'BLOB',
      'password_ciphertext': 'BLOB',
      'website_url_ciphertext': 'BLOB',
      'note_ciphertext': 'BLOB',
      'category_id': 'TEXT',
      'favorite': 'INTEGER',
      'created_at': 'INTEGER',
      'updated_at': 'INTEGER',
      'last_accessed_at': 'INTEGER',
      'deleted_at': 'INTEGER',
    },
    DatabaseSchema.noteItems: {
      'id': 'TEXT',
      'vault_id': 'TEXT',
      'title': 'TEXT',
      'content_ciphertext': 'BLOB',
      'summary_ciphertext': 'BLOB',
      'category_id': 'TEXT',
      'favorite': 'INTEGER',
      'created_at': 'INTEGER',
      'updated_at': 'INTEGER',
      'deleted_at': 'INTEGER',
    },
    DatabaseSchema.itemTags: {
      'item_id': 'TEXT',
      'item_type': 'TEXT',
      'tag_id': 'TEXT',
    },
    DatabaseSchema.modelRegistry: {
      'id': 'TEXT',
      'type': 'TEXT',
      'provider': 'TEXT',
      'name': 'TEXT',
      'version': 'TEXT',
      'size_bytes': 'INTEGER',
      'quantization': 'TEXT',
      'min_ram_mb': 'INTEGER',
      'recommended_tier': 'TEXT',
      'local_path': 'TEXT',
      'checksum': 'TEXT',
      'enabled': 'INTEGER',
      'installed_at': 'INTEGER',
    },
    DatabaseSchema.providerConfigs: {
      'id': 'TEXT',
      'provider_type': 'TEXT',
      'name': 'TEXT',
      'encrypted_config': 'BLOB',
      'enabled': 'INTEGER',
      'created_at': 'INTEGER',
      'updated_at': 'INTEGER',
    },
    DatabaseSchema.syncAccounts: {
      'id': 'TEXT',
      'provider_type': 'TEXT',
      'encrypted_config': 'BLOB',
      'last_sync_at': 'INTEGER',
      'status': 'TEXT',
      'created_at': 'INTEGER',
      'updated_at': 'INTEGER',
    },
    DatabaseSchema.appSettings: {'key': 'TEXT', 'value_ciphertext': 'BLOB'},
    DatabaseSchema.chatSessions: {
      'id': 'TEXT',
      'mode': 'TEXT',
      'title': 'TEXT',
      'allow_private_context': 'INTEGER',
      'last_model_id': 'TEXT',
      'archived': 'INTEGER',
      'created_at': 'INTEGER',
      'updated_at': 'INTEGER',
    },
    DatabaseSchema.chatMessages: {
      'id': 'TEXT',
      'session_id': 'TEXT',
      'role': 'TEXT',
      'content': 'TEXT',
      'status': 'TEXT',
      'used_private_context': 'INTEGER',
      'auto_retrieved_context_summary': 'TEXT',
      'manual_context_item_ids_json': 'TEXT',
      'related_source_ids_json': 'TEXT',
      'created_at': 'INTEGER',
    },
  };

  static const _notNullColumns = <String, Set<String>>{
    DatabaseSchema.vaults: {
      'name',
      'is_default',
      'encryption_version',
      'created_at',
      'updated_at',
    },
    DatabaseSchema.categories: {'vault_id', 'name', 'sort_order'},
    DatabaseSchema.tags: {'vault_id', 'name', 'created_at'},
    DatabaseSchema.secretItems: {
      'vault_id',
      'title',
      'favorite',
      'created_at',
      'updated_at',
    },
    DatabaseSchema.noteItems: {
      'vault_id',
      'title',
      'content_ciphertext',
      'favorite',
      'created_at',
      'updated_at',
    },
    DatabaseSchema.itemTags: {'item_id', 'item_type', 'tag_id'},
    DatabaseSchema.modelRegistry: {'type', 'provider', 'name', 'enabled'},
    DatabaseSchema.providerConfigs: {
      'provider_type',
      'name',
      'encrypted_config',
      'enabled',
      'created_at',
      'updated_at',
    },
    DatabaseSchema.syncAccounts: {
      'provider_type',
      'encrypted_config',
      'status',
      'created_at',
      'updated_at',
    },
    DatabaseSchema.appSettings: {'value_ciphertext'},
    DatabaseSchema.chatSessions: {
      'mode',
      'title',
      'allow_private_context',
      'archived',
      'created_at',
      'updated_at',
    },
    DatabaseSchema.chatMessages: {
      'session_id',
      'role',
      'content',
      'status',
      'used_private_context',
      'created_at',
    },
  };

  static Future<Set<String>> readTableNames(Database database) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows.map((row) => row['name']! as String).toSet();
  }

  static Future<bool> hasRequiredSchema(
    Database database,
    int sourceVersion,
    Set<String> actualTables,
  ) async {
    final requiredTables = sourceVersion == 1
        ? preservedTables.take(preservedTables.length - 2)
        : preservedTables;
    if (!actualTables.containsAll(requiredTables)) {
      return false;
    }
    for (final table in requiredTables) {
      final expectedColumns = _requiredColumns[table]!;
      final actualColumns = {
        for (final row in await database.rawQuery('PRAGMA table_info($table)'))
          row['name']! as String: row,
      };
      final primaryKeys = primaryKeyColumns[table]!;
      for (final entry in expectedColumns.entries) {
        final actual = actualColumns[entry.key];
        if (actual == null ||
            actual['type'].toString().toUpperCase() != entry.value ||
            (_notNullColumns[table]?.contains(entry.key) == true &&
                actual['notnull'] != 1) ||
            actual['pk'] != primaryKeys.indexOf(entry.key) + 1) {
          return false;
        }
      }
    }
    return true;
  }
}
