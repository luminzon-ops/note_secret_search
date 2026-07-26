import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_item_tag_store.dart';
import 'package:note_secret_search/features/secrets/application/secret_form_mapper.dart';
import 'package:note_secret_search/features/secrets/domain/secret_draft.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/recording_item_tag_store.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SecurityTestFixture security;
  late SqliteSecretRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    await _insertTestVault(database);
    security = SecurityTestFixture();
    repository = SqliteSecretRepository(database: database);
  });

  tearDown(() async {
    security.dispose();
    await database.close();
  });

  test('persists contextual NSSF fields and restores them', () async {
    final item = SecretFormMapper.create(
      vaultId: 'vault-1',
      draft: const SecretDraft(
        title: 'Mail',
        username: 'alice@example.com',
        password: 'private-password',
        websiteUrl: 'https://mail.example',
        note: 'personal',
        tags: ['mail'],
        categoryId: null,
        favorite: true,
      ),
      cryptoService: security.crypto,
    );

    await repository.save(item);

    final rawRows = await database.run(
      (db) => db.query(
        DatabaseSchema.secretItems,
        where: 'id = ?',
        whereArgs: [item.id],
      ),
    );
    expect(
      () => FieldEnvelopeCodec.decode(
        rawRows.single['password_ciphertext']! as List<int>,
      ),
      returnsNormally,
    );
    final restored = await repository.getById(item.id);
    expect(restored, isNotNull);
    expect(
      SecretFormMapper.toDraft(restored!, security.crypto).password,
      'private-password',
    );
    expect(restored.tags, ['mail']);
  });

  test('rejects legacy plaintext fields before saving', () async {
    final item = _legacySecret();

    await expectLater(repository.save(item), throwsFormatException);

    final rows = await database.run(
      (db) => db.query(
        DatabaseSchema.secretItems,
        where: 'id = ?',
        whereArgs: [item.id],
      ),
    );
    expect(rows, isEmpty);
  });

  test('rejects legacy plaintext fields loaded from the database', () async {
    final item = _legacySecret();
    await database.run(
      (db) => db.insert(DatabaseSchema.secretItems, {
        'id': item.id,
        'vault_id': item.vaultId,
        'title': item.title,
        'username_ciphertext': item.usernameCiphertext,
        'password_ciphertext': item.passwordCiphertext,
        'website_url_ciphertext': item.websiteUrlCiphertext,
        'note_ciphertext': item.noteCiphertext,
        'favorite': 0,
        'created_at': item.createdAt.millisecondsSinceEpoch,
        'updated_at': item.updatedAt.millisecondsSinceEpoch,
      }),
    );

    await expectLater(repository.getById(item.id), throwsFormatException);
  });

  test('rejects repository access after the database is locked', () async {
    await database.close();

    await expectLater(
      repository.getById('secret-1'),
      throwsA(isA<DatabaseAccessRevokedException>()),
    );
  });

  test('list batch loads tags with stable Vault ordering', () async {
    await database.run((db) async {
      await db.insert(DatabaseSchema.vaults, <String, Object?>{
        'id': 'vault-2',
        'name': 'Other Vault',
        'is_default': 0,
        'encryption_version': 1,
        'created_at': 2,
        'updated_at': 2,
      });
      for (final row in const <Map<String, Object?>>[
        <String, Object?>{
          'id': 'b-id',
          'vault_id': 'vault-1',
          'title': 'B',
          'favorite': 0,
          'created_at': 1,
          'updated_at': 2,
        },
        <String, Object?>{
          'id': 'a-id',
          'vault_id': 'vault-1',
          'title': 'A',
          'favorite': 0,
          'created_at': 1,
          'updated_at': 2,
        },
        <String, Object?>{
          'id': 'favorite-id',
          'vault_id': 'vault-1',
          'title': 'Favorite',
          'favorite': 1,
          'created_at': 1,
          'updated_at': 1,
        },
        <String, Object?>{
          'id': 'other-id',
          'vault_id': 'vault-2',
          'title': 'Other',
          'favorite': 1,
          'created_at': 1,
          'updated_at': 9,
        },
      ]) {
        await db.insert(DatabaseSchema.secretItems, row);
      }
    });
    final tagStore = RecordingItemTagStore(
      tagsByItemId: const <String, List<String>>{
        'favorite-id': <String>['favorite-tag'],
        'b-id': <String>['b-tag'],
      },
    );
    final listRepository = SqliteSecretRepository(
      database: database,
      tagStore: tagStore,
    );

    final items = await listRepository.listByVault('vault-1');

    expect(items.map((item) => item.id), <String>[
      'favorite-id',
      'a-id',
      'b-id',
    ]);
    expect(items.map((item) => item.tags), <List<String>>[
      <String>['favorite-tag'],
      <String>[],
      <String>['b-tag'],
    ]);
    expect(tagStore.loadCallCount, 1);
    expect(tagStore.lastItemIds, <String>['favorite-id', 'a-id', 'b-id']);
    expect(tagStore.lastItemType, ItemTagType.secret);
    expect(tagStore.lastVaultId, 'vault-1');
  });

  test('tag write failures roll back the item and embeddings', () async {
    final original = SecretFormMapper.create(
      vaultId: 'vault-1',
      draft: const SecretDraft(
        title: 'Original',
        username: 'alice',
        password: 'secret',
        websiteUrl: '',
        note: '',
        tags: <String>['old'],
        categoryId: null,
        favorite: false,
      ),
      cryptoService: security.crypto,
    );
    await repository.save(original);
    await _insertEmbedding(database, original.id, 'secret');
    final failingRepository = SqliteSecretRepository(
      database: database,
      tagStore: const _FailingItemTagStore(failReplace: true),
    );
    final updated = SecretFormMapper.update(
      previous: original,
      draft: const SecretDraft(
        title: 'Updated',
        username: 'bob',
        password: 'changed',
        websiteUrl: '',
        note: '',
        tags: <String>['new'],
        categoryId: null,
        favorite: true,
      ),
      cryptoService: security.crypto,
    );

    await expectLater(failingRepository.save(updated), throwsStateError);

    final restored = await repository.getById(original.id);
    expect(restored?.title, original.title);
    expect(restored?.tags, original.tags);
    final embeddings = await database.run(
      (db) => db.rawQuery(
        '''
        SELECT chunk.id
        FROM embedding_chunks chunk
        JOIN embedding_index_sets index_set
          ON index_set.id = chunk.index_set_id
        WHERE index_set.source_id = ?
          AND index_set.source_type = ?
        ''',
        <Object>[original.id, 'secret'],
      ),
    );
    expect(embeddings, hasLength(1));
  });

  test(
    'soft delete unlinks tags, preserves shared tags, and clears embeddings',
    () async {
      final lifecycleRepository = SqliteSecretRepository(
        database: database,
        nowMilliseconds: () => 1234,
      );
      final item = SecretFormMapper.create(
        vaultId: 'vault-1',
        draft: const SecretDraft(
          title: 'Delete me',
          username: 'alice',
          password: 'secret',
          websiteUrl: '',
          note: '',
          tags: <String>['shared', 'secret-only'],
          categoryId: null,
          favorite: false,
        ),
        cryptoService: security.crypto,
      );
      await lifecycleRepository.save(item);
      final sharedTag = await database.run((db) async {
        final row = (await db.query(
          DatabaseSchema.tags,
          columns: const <String>['id'],
          where: 'vault_id = ? AND name = ? COLLATE NOCASE',
          whereArgs: const <Object>['vault-1', 'shared'],
        )).single;
        return row['id']! as String;
      });
      await database.run((db) async {
        await db.insert(DatabaseSchema.noteItems, <String, Object?>{
          'id': 'note-shared',
          'vault_id': 'vault-1',
          'title': 'Shared owner',
          'content_ciphertext': item.passwordCiphertext,
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
        });
        await db.insert(DatabaseSchema.itemTags, <String, Object?>{
          'item_id': 'note-shared',
          'item_type': 'note',
          'tag_id': sharedTag,
        });
      });
      await _insertEmbedding(database, item.id, 'secret');

      await lifecycleRepository.softDelete(item.id);
      await lifecycleRepository.softDelete(item.id);

      final rawItem = await database.run(
        (db) => db.query(
          DatabaseSchema.secretItems,
          columns: const <String>['deleted_at'],
          where: 'id = ?',
          whereArgs: <Object>[item.id],
        ),
      );
      expect(rawItem.single['deleted_at'], 1234);
      expect(await lifecycleRepository.getById(item.id), isNull);
      expect(
        await database.run(
          (db) => db.query(
            DatabaseSchema.itemTags,
            where: 'item_id = ? AND item_type = ?',
            whereArgs: <Object>[item.id, 'secret'],
          ),
        ),
        isEmpty,
      );
      expect(
        await database.run(
          (db) => db.query(
            DatabaseSchema.tags,
            columns: const <String>['name'],
            orderBy: 'name COLLATE NOCASE ASC',
          ),
        ),
        const <Map<String, Object?>>[
          <String, Object?>{'name': 'shared'},
        ],
      );
      expect(
        await database.run((db) => db.query(DatabaseSchema.embeddingChunks)),
        isEmpty,
      );
    },
  );

  test('soft delete failures roll back the tombstone and cleanup', () async {
    final item = SecretFormMapper.create(
      vaultId: 'vault-1',
      draft: const SecretDraft(
        title: 'Keep me',
        username: 'alice',
        password: 'secret',
        websiteUrl: '',
        note: '',
        tags: <String>['old'],
        categoryId: null,
        favorite: false,
      ),
      cryptoService: security.crypto,
    );
    await repository.save(item);
    await _insertEmbedding(database, item.id, 'secret');
    final failingRepository = SqliteSecretRepository(
      database: database,
      tagStore: const _FailingItemTagStore(failUnlink: true),
      nowMilliseconds: () => 1234,
    );

    await expectLater(failingRepository.softDelete(item.id), throwsStateError);

    expect((await repository.getById(item.id))?.tags, item.tags);
    final rawItem = await database.run(
      (db) => db.query(
        DatabaseSchema.secretItems,
        columns: const <String>['deleted_at'],
        where: 'id = ?',
        whereArgs: <Object>[item.id],
      ),
    );
    expect(rawItem.single['deleted_at'], isNull);
    expect(
      await database.run((db) => db.query(DatabaseSchema.embeddingChunks)),
      hasLength(1),
    );
  });
}

SecretItem _legacySecret() {
  return SecretItem(
    id: 'legacy-secret',
    vaultId: 'vault-1',
    title: 'Legacy',
    usernameCiphertext: _legacyBytes('legacy-user'),
    passwordCiphertext: _legacyBytes('legacy-password'),
    websiteUrlCiphertext: null,
    noteCiphertext: null,
    tags: const [],
    categoryId: null,
    favorite: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );
}

Uint8List _legacyBytes(String value) => Uint8List.fromList(value.codeUnits);

Future<void> _insertTestVault(TestAppDatabase database) {
  return database.run(
    (db) => db.insert(DatabaseSchema.vaults, <String, Object?>{
      'id': 'vault-1',
      'name': 'Test Vault',
      'is_default': 0,
      'encryption_version': 1,
      'created_at': 1,
      'updated_at': 1,
    }),
  );
}

Future<void> _insertEmbedding(
  TestAppDatabase database,
  String sourceId,
  String sourceType,
) {
  return database.run((db) async {
    await db.insert(
      DatabaseSchema.modelRegistry,
      trustedModelRegistryRow(
        id: 'model-1',
        name: 'Test model',
        enabled: false,
      ),
    );
    await db.insert(DatabaseSchema.embeddingIndexSets, <String, Object?>{
      'id': 'embedding-set-1',
      'source_type': sourceType,
      'source_id': sourceId,
      'vault_id': 'vault-1',
      'model_id': 'model-1',
      'model_revision_hash': 'a' * 64,
      'source_updated_at': 1,
      'source_fingerprint': Uint8List(32),
      'fingerprint_key_id': 'test-key',
      'fingerprint_version': 1,
      'index_config_version': 1,
      'index_config_epoch': 1,
      'index_config_hash': 'b' * 64,
      'chunk_schema_version': 1,
      'vector_format_version': 1,
      'vector_dimension': 1,
      'chunk_count': 1,
      'created_at': 1,
    });
    await db.insert(DatabaseSchema.embeddingChunks, <String, Object?>{
      'id': 'embedding-1',
      'index_set_id': 'embedding-set-1',
      'source_field': 'secret.title',
      'field_chunk_index': 0,
      'chunk_fingerprint': Uint8List(32),
      'vector_blob': Uint8List(4),
      'token_count': 1,
      'created_at': 1,
    });
  });
}

class _FailingItemTagStore implements ItemTagStore {
  const _FailingItemTagStore({
    this.failReplace = false,
    this.failUnlink = false,
  });

  final bool failReplace;
  final bool failUnlink;

  @override
  Future<Map<String, List<String>>> loadTagsByItemIds(
    DatabaseExecutor executor, {
    required List<String> itemIds,
    required ItemTagType itemType,
    required String vaultId,
  }) async {
    return const <String, List<String>>{};
  }

  @override
  Future<void> replaceTags(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
    required List<String> tags,
  }) {
    if (failReplace) {
      throw StateError('injected_tag_failure');
    }
    return Future<void>.value();
  }

  @override
  Future<void> unlinkItem(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
  }) {
    if (failUnlink) {
      throw StateError('injected_tag_failure');
    }
    return Future<void>.value();
  }
}
