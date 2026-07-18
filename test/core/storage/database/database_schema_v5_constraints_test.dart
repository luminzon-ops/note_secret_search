import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('fresh v5 installs the ownership constraint inventory', () async {
    final database = await _openFreshV5();
    addTearDown(database.close);

    expect(
      await _foreignKeyTargets(database, 'secret_items'),
      const <String, String>{
        'vault_id': 'vaults:CASCADE',
        'category_id': 'categories:SET NULL',
      },
    );
    expect(
      await _foreignKeyTargets(database, 'note_items'),
      const <String, String>{
        'vault_id': 'vaults:CASCADE',
        'category_id': 'categories:SET NULL',
      },
    );
    expect(
      await _foreignKeyTargets(database, 'item_tags'),
      const <String, String>{'tag_id': 'tags:CASCADE'},
    );
    expect(
      await _foreignKeyTargets(database, 'embedding_chunks'),
      const <String, String>{'model_id': 'model_registry:CASCADE'},
    );
    expect(
      await _foreignKeyTargets(database, 'chat_messages'),
      const <String, String>{'session_id': 'chat_sessions:CASCADE'},
    );
    expect(await _objectNames(database, 'index'), _requiredV5Indexes);
    expect(await _objectNames(database, 'trigger'), _requiredV5Triggers);
  });

  test('v5 checks and business uniqueness reject invalid rows', () async {
    final database = await _openFreshV5();
    addTearDown(database.close);

    await expectLater(
      database.insert('vaults', <String, Object?>{
        'id': 'invalid-boolean',
        'name': 'Invalid',
        'is_default': 2,
        'encryption_version': 1,
        'created_at': 1,
        'updated_at': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      database.insert('vaults', <String, Object?>{
        'id': 'second-default',
        'name': 'Second',
        'is_default': 1,
        'encryption_version': 1,
        'created_at': 2,
        'updated_at': 2,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await database.insert('tags', <String, Object?>{
      'id': 'tag-a',
      'vault_id': 'default',
      'name': 'Work',
      'created_at': 1,
    });
    await expectLater(
      database.insert('tags', <String, Object?>{
        'id': 'tag-b',
        'vault_id': 'default',
        'name': 'work',
        'created_at': 2,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await database.insert('provider_configs', <String, Object?>{
      'id': 'provider-a',
      'provider_type': 'ollama',
      'name': 'A',
      'encrypted_config': Uint8List.fromList(const <int>[1]),
      'enabled': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    await expectLater(
      database.insert('provider_configs', <String, Object?>{
        'id': 'provider-b',
        'provider_type': 'ollama',
        'name': 'B',
        'encrypted_config': Uint8List.fromList(const <int>[2]),
        'enabled': 1,
        'created_at': 2,
        'updated_at': 2,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      database.insert('model_registry', <String, Object?>{
        'id': 'invalid-model',
        'type': 'embedding',
        'provider': 'local',
        'name': 'Invalid',
        'integrity_status': 'verified',
        'enabled': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      database.insert('download_tasks', <String, Object?>{
        'id': 'invalid-download',
        'model_id': 'model',
        'source_id': 'source',
        'status': 'running',
        'resumable': 1,
        'created_at': 1,
        'updated_at': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'v5 triggers preserve Vault ownership from every write direction',
    () async {
      final database = await _openFreshV5();
      addTearDown(database.close);
      await _insertOwnershipRows(database);

      await expectLater(
        database.insert('secret_items', <String, Object?>{
          'id': 'cross-category-secret',
          'vault_id': 'default',
          'title': 'Cross category',
          'category_id': 'category-vault-2',
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('item_tags', <String, Object?>{
          'item_id': 'secret-1',
          'item_type': 'secret',
          'tag_id': 'tag-vault-2',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('item_tags', <String, Object?>{
          'item_id': 'secret-deleted',
          'item_type': 'secret',
          'tag_id': 'tag-default',
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.insert('embedding_chunks', <String, Object?>{
          'id': 'missing-source',
          'source_id': 'missing',
          'source_type': 'secret',
          'chunk_index': 0,
          'plaintext_hash': 'hash',
          'model_id': 'model-1',
          'created_at': 1,
          'updated_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.update(
          'categories',
          <String, Object?>{'vault_id': 'vault-2'},
          where: 'id = ?',
          whereArgs: const <Object>['category-default'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.update(
          'tags',
          <String, Object?>{'vault_id': 'vault-2'},
          where: 'id = ?',
          whereArgs: const <Object>['tag-default'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.update(
          'secret_items',
          <String, Object?>{'vault_id': 'vault-2', 'category_id': null},
          where: 'id = ?',
          whereArgs: const <Object>['secret-1'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}

Future<Database> _openFreshV5() async {
  final directory = await Directory.systemTemp.createTemp(
    'note_secret_search_fresh_v5_',
  );
  addTearDown(() => directory.delete(recursive: true));
  final manager = DatabaseSchemaManager();
  return databaseFactoryFfi.openDatabase(
    '${directory.path}${Platform.pathSeparator}database.db',
    options: OpenDatabaseOptions(
      version: manager.version,
      onConfigure: manager.configure,
      onCreate: manager.create,
      onUpgrade: manager.upgrade,
      onDowngrade: manager.downgrade,
      singleInstance: false,
    ),
  );
}

Future<void> _insertOwnershipRows(Database database) async {
  await database.insert('vaults', <String, Object?>{
    'id': 'vault-2',
    'name': 'Second',
    'is_default': 0,
    'encryption_version': 1,
    'created_at': 2,
    'updated_at': 2,
  });
  await database.insert('categories', <String, Object?>{
    'id': 'category-default',
    'vault_id': 'default',
    'name': 'Default',
    'sort_order': 0,
  });
  await database.insert('categories', <String, Object?>{
    'id': 'category-vault-2',
    'vault_id': 'vault-2',
    'name': 'Second',
    'sort_order': 0,
  });
  await database.insert('tags', <String, Object?>{
    'id': 'tag-default',
    'vault_id': 'default',
    'name': 'default',
    'created_at': 1,
  });
  await database.insert('tags', <String, Object?>{
    'id': 'tag-vault-2',
    'vault_id': 'vault-2',
    'name': 'second',
    'created_at': 1,
  });
  await database.insert('secret_items', <String, Object?>{
    'id': 'secret-1',
    'vault_id': 'default',
    'title': 'Secret',
    'category_id': 'category-default',
    'favorite': 0,
    'created_at': 1,
    'updated_at': 1,
  });
  await database.insert('secret_items', <String, Object?>{
    'id': 'secret-deleted',
    'vault_id': 'default',
    'title': 'Deleted',
    'favorite': 0,
    'created_at': 1,
    'updated_at': 1,
    'deleted_at': 2,
  });
  await database.insert('item_tags', <String, Object?>{
    'item_id': 'secret-1',
    'item_type': 'secret',
    'tag_id': 'tag-default',
  });
  await database.insert('model_registry', <String, Object?>{
    'id': 'model-1',
    'type': 'embedding',
    'provider': 'local',
    'name': 'Model',
    'integrity_status': 'valid',
    'enabled': 1,
  });
}

Future<Map<String, String>> _foreignKeyTargets(
  Database database,
  String table,
) async {
  final rows = await database.rawQuery('PRAGMA foreign_key_list($table)');
  return <String, String>{
    for (final row in rows)
      row['from']! as String:
          '${row['table']! as String}:${row['on_delete']! as String}',
  };
}

Future<Set<String>> _objectNames(Database database, String type) async {
  final rows = await database.rawQuery(
    'SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE ?',
    <Object>[type, 'sqlite_%'],
  );
  return rows.map((row) => row['name']! as String).toSet();
}

const _requiredV5Indexes = <String>{
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

const _requiredV5Triggers = <String>{
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
