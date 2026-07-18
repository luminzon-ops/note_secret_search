import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/features/vault/domain/vault.dart';
import 'package:note_secret_search/features/vault/infrastructure/sqlite_vault_repository.dart';

import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SqliteVaultRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    repository = SqliteVaultRepository(database: database);
  });

  tearDown(() => database.close());

  test('updating a Vault preserves its child data', () async {
    await database.run(
      (executor) => executor.insert(
        DatabaseSchema.secretItems,
        <String, Object?>{
          'id': 'secret-1',
          'vault_id': 'default',
          'title': 'Preserved',
          'favorite': 0,
          'created_at': 1,
          'updated_at': 1,
        },
      ),
    );
    final original = (await repository.getDefaultVault())!;

    await repository.save(
      Vault(
        id: original.id,
        name: 'Renamed',
        description: original.description,
        isDefault: true,
        encryptionVersion: original.encryptionVersion,
        createdAt: original.createdAt,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
      ),
    );

    final children = await database.run(
      (executor) => executor.query(
        DatabaseSchema.secretItems,
        where: 'id = ?',
        whereArgs: const <Object>['secret-1'],
      ),
    );
    expect(children, hasLength(1));
  });

  test('saving a new default Vault switches the default atomically', () async {
    final second = Vault(
      id: 'vault-2',
      name: 'Second',
      description: null,
      isDefault: true,
      encryptionVersion: 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(2),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    );

    await repository.save(second);

    expect((await repository.getDefaultVault())?.id, second.id);
    final vaults = await repository.listAll();
    expect(vaults, hasLength(2));
    expect(vaults.where((vault) => vault.isDefault), hasLength(1));
    expect(
      vaults.singleWhere((vault) => vault.id == 'default').isDefault,
      isFalse,
    );
  });

  test('saving the only default Vault as non-default is rejected', () async {
    final original = (await repository.getDefaultVault())!;

    await expectLater(
      repository.save(
        Vault(
          id: original.id,
          name: original.name,
          description: original.description,
          isDefault: false,
          encryptionVersion: original.encryptionVersion,
          createdAt: original.createdAt,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
        ),
      ),
      throwsStateError,
    );

    expect((await repository.getDefaultVault())?.id, original.id);
  });
}
