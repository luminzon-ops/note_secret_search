import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_item_tag_store.dart';
import 'package:note_secret_search/features/notes/application/note_form_mapper.dart';
import 'package:note_secret_search/features/notes/domain/note_draft.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/secrets/application/secret_form_mapper.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  test(
    'replacing the same canonical tags preserves the index generation',
    () async {
      final database = await openTestAppDatabase();
      addTearDown(database.close);
      final tagStore = SqliteItemTagStore(
        idFactory: () => 'tag-work',
        nowMilliseconds: () => 1,
      );
      await _insertSecretAndModel(database);
      await database.transaction<void>((executor) {
        return tagStore.replaceTags(
          executor,
          itemId: 'secret-1',
          itemType: ItemTagType.secret,
          vaultId: 'default',
          tags: const <String>['Work'],
        );
      });
      await database.run(
        (executor) =>
            executor.insert(DatabaseSchema.embeddingIndexSets, _indexSetRow()),
      );

      await database.transaction<void>((executor) {
        return tagStore.replaceTags(
          executor,
          itemId: 'secret-1',
          itemType: ItemTagType.secret,
          vaultId: 'default',
          tags: const <String>[' work '],
        );
      });

      expect(
        await database.run(
          (executor) => executor.query(DatabaseSchema.embeddingIndexSets),
        ),
        hasLength(1),
      );
    },
  );

  test('hard deleting a source removes its index generation', () async {
    final database = await openTestAppDatabase();
    addTearDown(database.close);
    await _insertSecretAndModel(database);
    await database.run((executor) async {
      await executor.insert(DatabaseSchema.noteItems, <String, Object?>{
        'id': 'note-1',
        'vault_id': 'default',
        'title': 'Note',
        'content_ciphertext': Uint8List.fromList(const <int>[1]),
        'favorite': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await executor.insert(DatabaseSchema.embeddingIndexSets, _indexSetRow());
      await executor.insert(
        DatabaseSchema.embeddingIndexSets,
        _indexSetRow(id: 'set-note', sourceType: 'note', sourceId: 'note-1'),
      );
    });

    await database.transaction<void>((executor) async {
      await executor.delete(
        DatabaseSchema.secretItems,
        where: 'id = ?',
        whereArgs: const <Object>['secret-1'],
      );
      await executor.delete(
        DatabaseSchema.noteItems,
        where: 'id = ?',
        whereArgs: const <Object>['note-1'],
      );
    });

    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.embeddingIndexSets),
      ),
      isEmpty,
    );
  });

  test(
    'password and favorite only secret save preserves the index generation',
    () async {
      final database = await openTestAppDatabase();
      final security = SecurityTestFixture();
      addTearDown(() async {
        security.dispose();
        await database.close();
      });
      final repository = SqliteSecretRepository(database: database);
      final previous = _secret(security);
      await repository.save(previous);
      await database.run((executor) async {
        await _insertModel(executor);
        await executor.insert(
          DatabaseSchema.embeddingIndexSets,
          _indexSetRow(sourceId: previous.id),
        );
      });
      final draft = SecretFormMapper.toDraft(
        previous,
        security.crypto,
      ).copyWith(password: 'new-password', favorite: true);

      await repository.save(
        SecretFormMapper.update(
          previous: previous,
          draft: draft,
          cryptoService: security.crypto,
        ),
      );

      expect(
        await database.run(
          (executor) => executor.query(DatabaseSchema.embeddingIndexSets),
        ),
        hasLength(1),
      );
    },
  );

  test('favorite only note save preserves the index generation', () async {
    final database = await openTestAppDatabase();
    final security = SecurityTestFixture();
    addTearDown(() async {
      security.dispose();
      await database.close();
    });
    final repository = SqliteNoteRepository(database: database);
    final previous = _note(security);
    await repository.save(previous);
    await database.run((executor) async {
      await _insertModel(executor);
      await executor.insert(
        DatabaseSchema.embeddingIndexSets,
        _indexSetRow(
          id: 'set-note-form',
          sourceType: 'note',
          sourceId: previous.id,
        ),
      );
    });
    final previousDraft = NoteFormMapper.toDraft(previous, security.crypto);

    await repository.save(
      NoteFormMapper.update(
        previous: previous,
        draft: NoteDraft(
          title: previousDraft.title,
          content: previousDraft.content,
          summary: previousDraft.summary,
          tags: previousDraft.tags,
          categoryId: previousDraft.categoryId,
          favorite: true,
        ),
        cryptoService: security.crypto,
      ),
    );

    expect(
      await database.run(
        (executor) => executor.query(DatabaseSchema.embeddingIndexSets),
      ),
      hasLength(1),
    );
  });
}

Future<void> _insertSecretAndModel(TestAppDatabase database) {
  return database.run((executor) async {
    await executor.insert(DatabaseSchema.secretItems, <String, Object?>{
      'id': 'secret-1',
      'vault_id': 'default',
      'title': 'Secret',
      'favorite': 0,
      'created_at': 1,
      'updated_at': 1,
    });
    await _insertModel(executor);
  });
}

Future<void> _insertModel(DatabaseExecutor executor) {
  return executor.insert(DatabaseSchema.modelRegistry, <String, Object?>{
    'id': 'model-1',
    'type': 'embedding',
    'provider': 'local',
    'name': 'Embedding',
    'integrity_status': 'valid',
    'enabled': 1,
  });
}

SecretItem _secret(SecurityTestFixture security) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(1);
  return SecretItem(
    id: 'secret-form',
    vaultId: 'default',
    title: 'Account',
    usernameCiphertext: security.crypto.encryptField(
      'alice',
      field: EncryptedDatabaseField.secretUsername,
      rowId: 'secret-form',
    ),
    passwordCiphertext: security.crypto.encryptField(
      'old-password',
      field: EncryptedDatabaseField.secretPassword,
      rowId: 'secret-form',
    ),
    websiteUrlCiphertext: security.crypto.encryptField(
      'https://example.test',
      field: EncryptedDatabaseField.secretWebsiteUrl,
      rowId: 'secret-form',
    ),
    noteCiphertext: security.crypto.encryptField(
      'MFA enabled',
      field: EncryptedDatabaseField.secretNote,
      rowId: 'secret-form',
    ),
    tags: const <String>['Work'],
    categoryId: null,
    favorite: false,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

NoteItem _note(SecurityTestFixture security) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(1);
  return NoteItem(
    id: 'note-form',
    vaultId: 'default',
    title: 'Recovery',
    contentCiphertext: security.crypto.encryptField(
      'Recovery body',
      field: EncryptedDatabaseField.noteContent,
      rowId: 'note-form',
    )!,
    summaryCacheCiphertext: security.crypto.encryptField(
      'Recovery summary',
      field: EncryptedDatabaseField.noteSummary,
      rowId: 'note-form',
    ),
    tags: const <String>['Work'],
    categoryId: null,
    favorite: false,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Map<String, Object?> _indexSetRow({
  String id = 'set-1',
  String sourceType = 'secret',
  String sourceId = 'secret-1',
}) {
  return <String, Object?>{
    'id': id,
    'source_type': sourceType,
    'source_id': sourceId,
    'vault_id': 'default',
    'model_id': 'model-1',
    'model_revision_hash': 'a' * 64,
    'source_updated_at': 1,
    'source_fingerprint': Uint8List(32),
    'fingerprint_key_id': 'key-1',
    'fingerprint_version': 1,
    'index_config_version': 1,
    'index_config_epoch': 1,
    'index_config_hash': 'b' * 64,
    'chunk_schema_version': 1,
    'vector_format_version': 1,
    'vector_dimension': 0,
    'chunk_count': 0,
    'created_at': 1,
  };
}
