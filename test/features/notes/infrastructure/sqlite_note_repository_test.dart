import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_item_tag_store.dart';
import 'package:note_secret_search/features/notes/application/note_form_mapper.dart';
import 'package:note_secret_search/features/notes/domain/note_draft.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/recording_item_tag_store.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SecurityTestFixture security;
  late SqliteNoteRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    await _insertTestVault(database);
    security = SecurityTestFixture();
    repository = SqliteNoteRepository(database: database);
  });

  tearDown(() async {
    security.dispose();
    await database.close();
  });

  test('persists contextual NSSF fields and restores them', () async {
    final item = NoteFormMapper.create(
      vaultId: 'vault-1',
      draft: const NoteDraft(
        title: 'Recovery',
        content: 'private note body',
        summary: 'account recovery',
        tags: ['security'],
        categoryId: null,
        favorite: true,
      ),
      cryptoService: security.crypto,
    );

    await repository.save(item);

    final rawRows = await database.run(
      (db) => db.query(
        DatabaseSchema.noteItems,
        where: 'id = ?',
        whereArgs: [item.id],
      ),
    );
    expect(
      () => FieldEnvelopeCodec.decode(
        rawRows.single['content_ciphertext']! as List<int>,
      ),
      returnsNormally,
    );
    final restored = await repository.getById(item.id);
    expect(restored, isNotNull);
    expect(
      NoteFormMapper.toDraft(restored!, security.crypto).content,
      'private note body',
    );
    expect(restored.tags, ['security']);
  });

  test('rejects legacy plaintext fields before saving', () async {
    final item = _legacyNote();

    await expectLater(repository.save(item), throwsFormatException);

    final rows = await database.run(
      (db) => db.query(
        DatabaseSchema.noteItems,
        where: 'id = ?',
        whereArgs: [item.id],
      ),
    );
    expect(rows, isEmpty);
  });

  test('rejects legacy plaintext fields loaded from the database', () async {
    final item = _legacyNote();
    await database.run(
      (db) => db.insert(DatabaseSchema.noteItems, {
        'id': item.id,
        'vault_id': item.vaultId,
        'title': item.title,
        'content_ciphertext': item.contentCiphertext,
        'summary_ciphertext': item.summaryCacheCiphertext,
        'favorite': 0,
        'created_at': item.createdAt.millisecondsSinceEpoch,
        'updated_at': item.updatedAt.millisecondsSinceEpoch,
      }),
    );

    await expectLater(repository.getById(item.id), throwsFormatException);
  });

  test('list batch loads tags with stable Vault ordering', () async {
    final ciphertext = NoteFormMapper.create(
      vaultId: 'vault-1',
      draft: const NoteDraft(
        title: 'Ciphertext source',
        content: 'body',
        summary: '',
        tags: <String>[],
        categoryId: null,
        favorite: false,
      ),
      cryptoService: security.crypto,
    ).contentCiphertext;
    await database.run((db) async {
      await db.insert(DatabaseSchema.vaults, <String, Object?>{
        'id': 'vault-2',
        'name': 'Other Vault',
        'is_default': 0,
        'encryption_version': 1,
        'created_at': 2,
        'updated_at': 2,
      });
      for (final row in <Map<String, Object?>>[
        <String, Object?>{
          'id': 'b-id',
          'vault_id': 'vault-1',
          'title': 'B',
          'content_ciphertext': ciphertext,
          'favorite': 0,
          'created_at': 1,
          'updated_at': 2,
        },
        <String, Object?>{
          'id': 'a-id',
          'vault_id': 'vault-1',
          'title': 'A',
          'content_ciphertext': ciphertext,
          'favorite': 0,
          'created_at': 1,
          'updated_at': 2,
        },
        <String, Object?>{
          'id': 'favorite-id',
          'vault_id': 'vault-1',
          'title': 'Favorite',
          'content_ciphertext': ciphertext,
          'favorite': 1,
          'created_at': 1,
          'updated_at': 1,
        },
        <String, Object?>{
          'id': 'other-id',
          'vault_id': 'vault-2',
          'title': 'Other',
          'content_ciphertext': ciphertext,
          'favorite': 1,
          'created_at': 1,
          'updated_at': 9,
        },
      ]) {
        await db.insert(DatabaseSchema.noteItems, row);
      }
    });
    final tagStore = RecordingItemTagStore(
      tagsByItemId: const <String, List<String>>{
        'favorite-id': <String>['favorite-tag'],
        'b-id': <String>['b-tag'],
      },
    );
    final listRepository = SqliteNoteRepository(
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
    expect(tagStore.lastItemType, ItemTagType.note);
    expect(tagStore.lastVaultId, 'vault-1');
  });

  test('tag write failures roll back the item and embeddings', () async {
    final original = NoteFormMapper.create(
      vaultId: 'vault-1',
      draft: const NoteDraft(
        title: 'Original',
        content: 'old body',
        summary: 'old summary',
        tags: <String>['old'],
        categoryId: null,
        favorite: false,
      ),
      cryptoService: security.crypto,
    );
    await repository.save(original);
    await _insertEmbedding(database, original.id, 'note');
    final failingRepository = SqliteNoteRepository(
      database: database,
      tagStore: const _FailingItemTagStore(),
    );
    final updated = NoteFormMapper.update(
      previous: original,
      draft: const NoteDraft(
        title: 'Updated',
        content: 'new body',
        summary: 'new summary',
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
        <Object>[original.id, 'note'],
      ),
    );
    expect(embeddings, hasLength(1));
  });

  test('soft delete removes note tags and embeddings idempotently', () async {
    var nextTimestamp = 5678;
    final lifecycleRepository = SqliteNoteRepository(
      database: database,
      nowMilliseconds: () {
        final value = nextTimestamp;
        nextTimestamp = 9999;
        return value;
      },
    );
    final item = NoteFormMapper.create(
      vaultId: 'vault-1',
      draft: const NoteDraft(
        title: 'Delete me',
        content: 'body',
        summary: '',
        tags: <String>['note-only'],
        categoryId: null,
        favorite: false,
      ),
      cryptoService: security.crypto,
    );
    await lifecycleRepository.save(item);
    await _insertEmbedding(database, item.id, 'note');

    await lifecycleRepository.softDelete(item.id);
    await lifecycleRepository.softDelete(item.id);

    expect(await lifecycleRepository.getById(item.id), isNull);
    final rawItem = await database.run(
      (db) => db.query(
        DatabaseSchema.noteItems,
        columns: const <String>['deleted_at'],
        where: 'id = ?',
        whereArgs: <Object>[item.id],
      ),
    );
    expect(rawItem.single['deleted_at'], 5678);
    expect(
      await database.run((db) => db.query(DatabaseSchema.itemTags)),
      isEmpty,
    );
    expect(await database.run((db) => db.query(DatabaseSchema.tags)), isEmpty);
    expect(
      await database.run((db) => db.query(DatabaseSchema.embeddingChunks)),
      isEmpty,
    );
  });
}

NoteItem _legacyNote() {
  return NoteItem(
    id: 'legacy-note',
    vaultId: 'vault-1',
    title: 'Legacy',
    contentCiphertext: _legacyBytes('legacy body'),
    summaryCacheCiphertext: _legacyBytes('legacy summary'),
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
      'source_field': 'note.title',
      'field_chunk_index': 0,
      'chunk_fingerprint': Uint8List(32),
      'vector_blob': Uint8List(4),
      'token_count': 1,
      'created_at': 1,
    });
  });
}

class _FailingItemTagStore implements ItemTagStore {
  const _FailingItemTagStore();

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
    throw StateError('injected_tag_failure');
  }

  @override
  Future<void> unlinkItem(
    DatabaseExecutor executor, {
    required String itemId,
    required ItemTagType itemType,
    required String vaultId,
  }) async {}
}
