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
      (db) => db.query(
        DatabaseSchema.embeddingChunks,
        where: 'source_id = ? AND source_type = ?',
        whereArgs: <Object>[original.id, 'note'],
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
    expect(
      await database.run((db) => db.query(DatabaseSchema.tags)),
      isEmpty,
    );
    expect(
      await database.run(
        (db) => db.query(DatabaseSchema.embeddingChunks),
      ),
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
    await db.insert(DatabaseSchema.modelRegistry, <String, Object?>{
      'id': 'model-1',
      'type': 'embedding',
      'provider': 'local',
      'name': 'Test model',
      'integrity_status': 'valid',
      'enabled': 0,
    });
    await db.insert(DatabaseSchema.embeddingChunks, <String, Object?>{
      'id': 'embedding-1',
      'source_id': sourceId,
      'source_type': sourceType,
      'chunk_index': 0,
      'plaintext_hash': 'hash',
      'model_id': 'model-1',
      'created_at': 1,
      'updated_at': 1,
    });
  });
}

class _FailingItemTagStore implements ItemTagStore {
  const _FailingItemTagStore();

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
