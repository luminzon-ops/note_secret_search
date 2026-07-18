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
      (executor) => executor.insert(
        DatabaseSchema.secretItems,
        <String, Object?>{
          'id': 'secret-1',
          'vault_id': 'default',
          'title': 'Secret',
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
        },
      ),
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
}
