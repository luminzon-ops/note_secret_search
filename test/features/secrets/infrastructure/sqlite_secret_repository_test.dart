import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/core/storage/database/app_database.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/secrets/application/secret_form_mapper.dart';
import 'package:note_secret_search/features/secrets/domain/secret_draft.dart';
import 'package:note_secret_search/features/secrets/domain/secret_item.dart';
import 'package:note_secret_search/features/secrets/infrastructure/sqlite_secret_repository.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/domain/vault_repository.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SecurityTestFixture security;
  late SqliteSecretRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    security = SecurityTestFixture();
    repository = SqliteSecretRepository(
      database: database,
      vaultRepository: _TestVaultRepository(),
    );
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

class _TestVaultRepository implements VaultRepository {
  @override
  Future<Vault?> getDefaultVault() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
