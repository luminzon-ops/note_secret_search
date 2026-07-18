import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/legacy_database_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'dirty v4 data is normalized deterministically before rebuild',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.freshV4,
      );
      addTearDown(fixture.dispose);
      final raw = await databaseFactoryFfi.openDatabase(
        fixture.sourcePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await _makeDirtyV4(raw);
      await raw.close();

      final manager = DatabaseSchemaManager();
      final database = await _openManagedDatabase(fixture.sourcePath, manager);
      addTearDown(database.close);

      expect(
        await database.query(
          'vaults',
          columns: const <String>['id'],
          where: 'is_default = 1',
        ),
        const <Map<String, Object?>>[
          <String, Object?>{'id': 'vault-1'},
        ],
      );
      expect(
        await database.query(
          'categories',
          columns: const <String>['id'],
          orderBy: 'id',
        ),
        const <Map<String, Object?>>[
          <String, Object?>{'id': 'category-duplicate'},
          <String, Object?>{'id': 'category-other-vault'},
        ],
      );
      expect(
        (await database.query(
          'secret_items',
          columns: const <String>['category_id'],
          where: 'id = ?',
          whereArgs: const <Object>['secret-1'],
        )).single['category_id'],
        'category-duplicate',
      );
      expect(
        (await database.query(
          'note_items',
          columns: const <String>['category_id'],
          where: 'id = ?',
          whereArgs: const <Object>['note-1'],
        )).single['category_id'],
        isNull,
      );
      expect(
        await database.query(
          'tags',
          columns: const <String>['id'],
          orderBy: 'id',
        ),
        const <Map<String, Object?>>[
          <String, Object?>{'id': 'tag-1'},
        ],
      );
      expect(
        await database.query(
          'item_tags',
          orderBy: 'item_type, item_id, tag_id',
        ),
        const <Map<String, Object?>>[
          <String, Object?>{
            'item_id': 'note-1',
            'item_type': 'note',
            'tag_id': 'tag-1',
          },
          <String, Object?>{
            'item_id': 'secret-1',
            'item_type': 'secret',
            'tag_id': 'tag-1',
          },
        ],
      );
      expect(await database.query('embedding_chunks'), isEmpty);

      final models = {
        for (final row in await database.query('model_registry'))
          row['id']! as String: row,
      };
      expect(models['model-1']!['integrity_status'], 'valid');
      expect(
        jsonDecode(models['model-1']!['artifact_paths_json']! as String),
        const <Object?>[
          <String, Object?>{
            'role': 'model',
            'local_path': '/models/legacy.onnx',
          },
        ],
      );
      expect(models['model-invalid']!['integrity_status'], 'unknown');
      final providers = {
        for (final row in await database.query('provider_configs'))
          row['id']! as String: row['enabled'],
      };
      expect(providers, <String, Object?>{
        'provider-1': 0,
        'provider-latest': 1,
      });
    },
  );

  test(
    'legacy multi-file artifact arrays receive deterministic roles',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.freshV4,
      );
      addTearDown(fixture.dispose);
      final raw = await databaseFactoryFfi.openDatabase(
        fixture.sourcePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await raw.insert('model_registry', <String, Object?>{
        'id': 'model-multi',
        'type': 'multimodal_llm',
        'provider': 'local',
        'name': 'Legacy multimodal',
        'local_path': '/models/model.gguf',
        'artifact_paths_json':
            '["/models/model.gguf","/models/mmproj.gguf",'
            '"/models/tokenizer.json"]',
        'integrity_status': 'valid',
        'enabled': 1,
      });
      await raw.close();

      final database = await _openManagedDatabase(
        fixture.sourcePath,
        DatabaseSchemaManager(),
      );
      addTearDown(database.close);
      final row = (await database.query(
        'model_registry',
        columns: const <String>['artifact_paths_json'],
        where: 'id = ?',
        whereArgs: const <Object>['model-multi'],
      )).single;

      expect(jsonDecode(row['artifact_paths_json']! as String), <Object?>[
        <String, Object?>{'role': 'model', 'local_path': '/models/model.gguf'},
        <String, Object?>{
          'role': 'mmproj',
          'local_path': '/models/mmproj.gguf',
        },
        <String, Object?>{
          'role': 'artifact_2',
          'local_path': '/models/tokenizer.json',
        },
      ]);
    },
  );
}

Future<void> _makeDirtyV4(Database database) async {
  const createdAt = 1_700_000_000_000;
  await database.insert('vaults', <String, Object?>{
    'id': 'vault-2',
    'name': 'Secondary',
    'description': null,
    'is_default': 1,
    'encryption_version': 1,
    'created_at': createdAt + 20,
    'updated_at': createdAt + 20,
  });
  await database.insert('categories', <String, Object?>{
    'id': 'category-duplicate',
    'vault_id': 'vault-1',
    'name': 'logins',
    'sort_order': 1,
  });
  await database.insert('categories', <String, Object?>{
    'id': 'category-other-vault',
    'vault_id': 'vault-2',
    'name': 'Other',
    'sort_order': 0,
  });
  await database.update(
    'note_items',
    <String, Object?>{'category_id': 'category-other-vault'},
    where: 'id = ?',
    whereArgs: const <Object>['note-1'],
  );
  await database.insert('tags', <String, Object?>{
    'id': 'tag-duplicate',
    'vault_id': 'vault-1',
    'name': 'WORK',
    'created_at': createdAt + 1,
  });
  await database.insert('tags', <String, Object?>{
    'id': 'tag-other-vault',
    'vault_id': 'vault-2',
    'name': 'other',
    'created_at': createdAt,
  });
  await database.insert('tags', <String, Object?>{
    'id': 'tag-orphan',
    'vault_id': 'vault-1',
    'name': 'orphan',
    'created_at': createdAt,
  });
  await database.insert('item_tags', <String, Object?>{
    'item_id': 'note-1',
    'item_type': 'note',
    'tag_id': 'tag-duplicate',
  });
  await database.insert('item_tags', <String, Object?>{
    'item_id': 'secret-1',
    'item_type': 'secret',
    'tag_id': 'tag-other-vault',
  });
  await database.insert('item_tags', <String, Object?>{
    'item_id': 'secret-deleted',
    'item_type': 'secret',
    'tag_id': 'tag-1',
  });
  await database.insert('item_tags', <String, Object?>{
    'item_id': 'missing-secret',
    'item_type': 'secret',
    'tag_id': 'tag-1',
  });
  await database.update(
    'model_registry',
    <String, Object?>{
      'artifact_paths_json': '["/models/legacy.onnx"]',
      'integrity_status': 'verified',
    },
    where: 'id = ?',
    whereArgs: const <Object>['model-1'],
  );
  await database.insert('model_registry', <String, Object?>{
    'id': 'model-invalid',
    'type': 'llm',
    'provider': 'local',
    'name': 'Invalid legacy state',
    'artifact_paths_json': '[]',
    'integrity_status': 'legacy-bad-value',
    'enabled': 0,
  });
  final provider = (await database.query(
    'provider_configs',
    columns: const <String>['encrypted_config'],
    where: 'id = ?',
    whereArgs: const <Object>['provider-1'],
  )).single;
  await database.insert('provider_configs', <String, Object?>{
    'id': 'provider-latest',
    'provider_type': 'openAiCompatible',
    'name': 'Latest',
    'encrypted_config': provider['encrypted_config'],
    'enabled': 1,
    'created_at': createdAt + 1,
    'updated_at': createdAt + 10,
  });
}

Future<Database> _openManagedDatabase(
  String path,
  DatabaseSchemaManager manager,
) {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: DatabaseSchemaManager.latestVersion,
      onConfigure: manager.configure,
      onCreate: manager.create,
      onUpgrade: manager.upgrade,
      onDowngrade: manager.downgrade,
      singleInstance: false,
    ),
  );
}
