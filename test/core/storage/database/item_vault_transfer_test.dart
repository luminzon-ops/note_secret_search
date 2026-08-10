import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/notes/application/note_form_mapper.dart';
import 'package:note_secret_search/features/notes/domain/note_draft.dart';
import 'package:note_secret_search/features/notes/domain/note_item.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/secrets/application/secret_form_mapper.dart';
import 'package:note_secret_search/features/secrets/domain/secret_draft.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SecurityTestFixture security;

  setUp(() async {
    database = await openTestAppDatabase();
    security = SecurityTestFixture();
    await database.run((executor) async {
      for (final id in const <String>['vault-1', 'vault-2']) {
        await executor.insert(DatabaseSchema.vaults, <String, Object?>{
          'id': id,
          'name': id,
          'is_default': 0,
          'encryption_version': 1,
          'created_at': 1,
          'updated_at': 1,
        });
      }
    });
  });

  tearDown(() async {
    security.dispose();
    await database.close();
  });

  test('Secret with old tags moves to a new Vault atomically', () async {
    final repository = SqliteSecretRepository(database: database);
    final original = SecretFormMapper.create(
      vaultId: 'vault-1',
      draft: const SecretDraft(
        title: 'Secret',
        username: 'alice',
        password: 'password',
        websiteUrl: '',
        note: '',
        tags: <String>['old-tag'],
        categoryId: null,
        favorite: false,
      ),
      cryptoService: security.crypto,
    );
    await repository.save(original);

    await repository.save(
      SecretItem(
        id: original.id,
        vaultId: 'vault-2',
        title: original.title,
        usernameCiphertext: original.usernameCiphertext,
        passwordCiphertext: original.passwordCiphertext,
        websiteUrlCiphertext: original.websiteUrlCiphertext,
        noteCiphertext: original.noteCiphertext,
        tags: const <String>['new-tag'],
        categoryId: null,
        favorite: original.favorite,
        createdAt: original.createdAt,
        updatedAt: original.updatedAt.add(const Duration(seconds: 1)),
      ),
    );

    final restored = await repository.getById(original.id);
    expect(restored?.vaultId, 'vault-2');
    expect(restored?.tags, const <String>['new-tag']);
    await _expectOnlyDestinationTag(database);
  });

  test('Note with old tags moves to a new Vault atomically', () async {
    final repository = SqliteNoteRepository(database: database);
    final original = NoteFormMapper.create(
      vaultId: 'vault-1',
      draft: const NoteDraft(
        title: 'Note',
        content: 'body',
        summary: '',
        tags: <String>['old-tag'],
        categoryId: null,
        favorite: false,
      ),
      cryptoService: security.crypto,
    );
    await repository.save(original);

    await repository.save(
      NoteItem(
        id: original.id,
        vaultId: 'vault-2',
        title: original.title,
        contentCiphertext: original.contentCiphertext,
        summaryCacheCiphertext: original.summaryCacheCiphertext,
        tags: const <String>['new-tag'],
        categoryId: null,
        favorite: original.favorite,
        createdAt: original.createdAt,
        updatedAt: original.updatedAt.add(const Duration(seconds: 1)),
      ),
    );

    final restored = await repository.getById(original.id);
    expect(restored?.vaultId, 'vault-2');
    expect(restored?.tags, const <String>['new-tag']);
    await _expectOnlyDestinationTag(database);
  });
}

Future<void> _expectOnlyDestinationTag(TestAppDatabase database) async {
  final tags = await database.run(
    (executor) => executor.query(
      DatabaseSchema.tags,
      columns: const <String>['vault_id', 'name'],
    ),
  );
  expect(tags, const <Map<String, Object?>>[
    <String, Object?>{'vault_id': 'vault-2', 'name': 'new-tag'},
  ]);
}
