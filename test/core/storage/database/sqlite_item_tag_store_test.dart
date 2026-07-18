import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_item_tag_store.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  test('replaces tags with canonical names and deletes orphans', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    final generatedIds = <String>[
      'tag-generated-1',
      'tag-generated-2',
      'tag-generated-3',
    ];
    final store = SqliteItemTagStore(
      idFactory: () => generatedIds.removeAt(0),
      nowMilliseconds: () => 100,
    );
    await database.run(
      (executor) =>
          executor.insert(DatabaseSchema.secretItems, <String, Object?>{
            'id': 'secret-1',
            'vault_id': 'default',
            'title': 'Secret',
            'favorite': 0,
            'created_at': 1,
            'updated_at': 1,
          }),
    );

    await database.transaction<void>((executor) {
      return store.replaceTags(
        executor,
        itemId: 'secret-1',
        itemType: ItemTagType.secret,
        vaultId: 'default',
        tags: const <String>[' Work ', 'work', '', 'x:y', 'x:y'],
      );
    });
    await database.transaction<void>((executor) {
      return store.replaceTags(
        executor,
        itemId: 'secret-1',
        itemType: ItemTagType.secret,
        vaultId: 'default',
        tags: const <String>['WORK', 'New'],
      );
    });

    final tags = await database.run(
      (executor) => executor.query(
        DatabaseSchema.tags,
        columns: const <String>['id', 'name'],
        orderBy: 'name COLLATE NOCASE ASC',
      ),
    );
    expect(tags, const <Map<String, Object?>>[
      <String, Object?>{'id': 'tag-generated-3', 'name': 'New'},
      <String, Object?>{'id': 'tag-generated-1', 'name': 'Work'},
    ]);
    final links = await database.run(
      (executor) => executor.query(
        DatabaseSchema.itemTags,
        columns: const <String>['tag_id'],
        orderBy: 'tag_id ASC',
      ),
    );
    expect(links, const <Map<String, Object?>>[
      <String, Object?>{'tag_id': 'tag-generated-1'},
      <String, Object?>{'tag_id': 'tag-generated-3'},
    ]);
  });

  test('batch loads tags without crossing item type or Vault', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    final generatedIds = <String>[
      'tag-secret-alpha',
      'tag-secret-zulu',
      'tag-note',
      'tag-other-vault',
    ];
    final store = SqliteItemTagStore(
      idFactory: () => generatedIds.removeAt(0),
      nowMilliseconds: () => 100,
    );
    await database.run((executor) async {
      await executor.insert(DatabaseSchema.vaults, <String, Object?>{
        'id': 'vault-2',
        'name': 'Second Vault',
        'is_default': 0,
        'encryption_version': 1,
        'created_at': 2,
        'updated_at': 2,
      });
      await executor.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': 'shared-id',
        'vault_id': 'default',
        'title': 'Secret',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await executor.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': 'empty-secret',
        'vault_id': 'default',
        'title': 'Empty',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await executor.insert(DatabaseSchema.noteItems, <String, Object?>{
        'id': 'shared-id',
        'vault_id': 'default',
        'title': 'Note',
        'content_ciphertext': Uint8List.fromList(<int>[1]),
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await executor.insert(DatabaseSchema.secretItems, <String, Object?>{
        'id': 'other-secret',
        'vault_id': 'vault-2',
        'title': 'Other',
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
    });
    await database.transaction<void>((executor) async {
      await store.replaceTags(
        executor,
        itemId: 'shared-id',
        itemType: ItemTagType.secret,
        vaultId: 'default',
        tags: const <String>['Zulu', 'alpha'],
      );
      await store.replaceTags(
        executor,
        itemId: 'shared-id',
        itemType: ItemTagType.note,
        vaultId: 'default',
        tags: const <String>['note-only'],
      );
      await store.replaceTags(
        executor,
        itemId: 'other-secret',
        itemType: ItemTagType.secret,
        vaultId: 'vault-2',
        tags: const <String>['other-vault'],
      );
    });

    final tags = await database.run(
      (executor) => store.loadTagsByItemIds(
        executor,
        itemIds: const <String>['shared-id', 'empty-secret', 'other-secret'],
        itemType: ItemTagType.secret,
        vaultId: 'default',
      ),
    );

    expect(tags, const <String, List<String>>{
      'shared-id': <String>['alpha', 'Zulu'],
      'empty-secret': <String>[],
      'other-secret': <String>[],
    });
  });
}
