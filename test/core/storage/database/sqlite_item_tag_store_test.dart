import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_item_tag_store.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

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

  test(
    'batch tag loading keeps every query scoped to at most 200 ids',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      final store = SqliteItemTagStore();
      final itemIds = List<String>.generate(
        1001,
        (index) => 'secret-$index',
        growable: false,
      );
      late _BindLimitedExecutor limited;

      final tags = await database.run((executor) {
        limited = _BindLimitedExecutor(executor, maxBindVariables: 999);
        return store.loadTagsByItemIds(
          limited,
          itemIds: itemIds,
          itemType: ItemTagType.secret,
          vaultId: 'default',
        );
      });

      expect(limited.rawQueryCount, 6);
      expect(
        limited.sqlStatements,
        everyElement(contains('link.item_id IN (')),
      );
      expect(
        limited.argumentLists.map((arguments) => arguments.length),
        everyElement(lessThanOrEqualTo(203)),
      );
      expect(tags, hasLength(itemIds.length));
      expect(tags.values, everyElement(isEmpty));
    },
  );

  test('single item tag loading binds the requested item id', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    final store = SqliteItemTagStore();
    late _BindLimitedExecutor limited;

    await database.run((executor) {
      limited = _BindLimitedExecutor(executor, maxBindVariables: 999);
      return store.loadTagsByItemIds(
        limited,
        itemIds: const <String>['secret-1'],
        itemType: ItemTagType.secret,
        vaultId: 'default',
      );
    });

    expect(limited.lastSql, contains('link.item_id IN (?)'));
    expect(limited.lastArguments, const <Object?>[
      'secret',
      'default',
      'default',
      'secret-1',
    ]);
  });
}

class _BindLimitedExecutor implements DatabaseExecutor {
  _BindLimitedExecutor(this._delegate, {required this.maxBindVariables});

  final DatabaseExecutor _delegate;
  final int maxBindVariables;
  int rawQueryCount = 0;
  String? lastSql;
  List<Object?>? lastArguments;
  final List<String> sqlStatements = <String>[];
  final List<List<Object?>> argumentLists = <List<Object?>>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    rawQueryCount += 1;
    lastSql = sql;
    lastArguments = arguments;
    sqlStatements.add(sql);
    argumentLists.add(List<Object?>.unmodifiable(arguments ?? const []));
    if ((arguments?.length ?? 0) > maxBindVariables) {
      throw StateError('sqlite_bind_limit_exceeded');
    }
    return _delegate.rawQuery(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected database call: ${invocation.memberName}',
    );
  }
}
