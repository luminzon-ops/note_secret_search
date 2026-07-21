import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/crypto_service.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/notes/infrastructure/sqlite_note_repository.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  test(
    'secret keyset pages and id hydration stay scoped and complete',
    () async {
      final database = await openTestAppDatabase();
      final security = SecurityTestFixture();
      addTearDown(() async {
        security.dispose();
        await database.close();
      });
      await _insertVaults(database);
      await database.run((db) async {
        for (var index = 0; index < 260; index++) {
          final id = 'secret-${index.toString().padLeft(3, '0')}';
          await db.insert(DatabaseSchema.secretItems, <String, Object?>{
            'id': id,
            'vault_id': 'vault-1',
            'title': 'Secret $index',
            'favorite': 0,
            'created_at': index,
            'updated_at': index,
          });
        }
        await db.insert(DatabaseSchema.secretItems, <String, Object?>{
          'id': 'secret-deleted',
          'vault_id': 'vault-1',
          'title': 'Deleted',
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
          'deleted_at': 1,
        });
        await db.insert(DatabaseSchema.secretItems, <String, Object?>{
          'id': 'secret-other-vault',
          'vault_id': 'vault-2',
          'title': 'Other vault',
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
        });
      });

      final repository = SqliteSecretRepository(database: database);
      final first = await repository.listByVaultPage('vault-1', limit: 128);
      final second = await repository.listByVaultPage(
        'vault-1',
        afterId: first.last.id,
        limit: 128,
      );
      final third = await repository.listByVaultPage(
        'vault-1',
        afterId: second.last.id,
        limit: 128,
      );

      expect(first, hasLength(128));
      expect(second, hasLength(128));
      expect(third, hasLength(4));
      final all = [...first, ...second, ...third];
      expect(
        all.map((item) => item.id),
        orderedEquals([
          for (var index = 0; index < 260; index++)
            'secret-${index.toString().padLeft(3, '0')}',
        ]),
      );

      final hydrated = await repository
          .listByVaultIds('vault-1', const <String>[
            'secret-000',
            'secret-129',
            'secret-259',
            'secret-deleted',
            'secret-other-vault',
          ]);
      expect(
        hydrated.map((item) => item.id),
        orderedEquals(const <String>['secret-000', 'secret-129', 'secret-259']),
      );
    },
  );

  test('note id hydration excludes deleted and other-vault rows', () async {
    final database = await openTestAppDatabase();
    final security = SecurityTestFixture();
    addTearDown(() async {
      security.dispose();
      await database.close();
    });
    await _insertVaults(database);
    final ciphertext = security.crypto.encryptField(
      'body',
      field: EncryptedDatabaseField.noteContent,
      rowId: 'note-1',
    )!;
    await database.run((db) async {
      for (final row in <Map<String, Object?>>[
        <String, Object?>{
          'id': 'note-1',
          'vault_id': 'vault-1',
          'title': 'One',
          'content_ciphertext': ciphertext,
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
        },
        <String, Object?>{
          'id': 'note-deleted',
          'vault_id': 'vault-1',
          'title': 'Deleted',
          'content_ciphertext': ciphertext,
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
          'deleted_at': 1,
        },
        <String, Object?>{
          'id': 'note-other-vault',
          'vault_id': 'vault-2',
          'title': 'Other',
          'content_ciphertext': ciphertext,
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
        },
      ]) {
        await db.insert(DatabaseSchema.noteItems, row);
      }
    });

    final repository = SqliteNoteRepository(database: database);
    final hydrated = await repository.listByVaultIds('vault-1', const <String>[
      'note-1',
      'note-deleted',
      'note-other-vault',
    ]);

    expect(hydrated.map((item) => item.id), const <String>['note-1']);
  });
}

Future<void> _insertVaults(TestAppDatabase database) {
  return database.run((db) async {
    for (final row in const <Map<String, Object?>>[
      <String, Object?>{
        'id': 'vault-1',
        'name': 'Vault 1',
        'is_default': 0,
        'encryption_version': 1,
        'created_at': 1,
        'updated_at': 1,
      },
      <String, Object?>{
        'id': 'vault-2',
        'name': 'Vault 2',
        'is_default': 0,
        'encryption_version': 1,
        'created_at': 1,
        'updated_at': 1,
      },
    ]) {
      await db.insert(DatabaseSchema.vaults, row);
    }
  });
}
