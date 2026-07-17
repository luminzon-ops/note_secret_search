import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/core/security/field_crypto.dart';
import 'package:note_secret_search/core/security/field_envelope.dart';
import 'package:note_secret_search/core/storage/database/database_schema.dart';
import 'package:note_secret_search/core/storage/database/sqlite_protected_configuration_repository.dart';

import '../../../support/security_test_fixture.dart';
import '../../../support/sqlite_test_database.dart';

void main() {
  late TestAppDatabase database;
  late SecurityTestFixture security;
  late SqliteProtectedConfigurationRepository repository;

  setUp(() async {
    database = await openTestAppDatabase();
    security = SecurityTestFixture();
    repository = SqliteProtectedConfigurationRepository(
      database: database,
      cryptoService: security.crypto,
    );
  });

  tearDown(() async {
    security.dispose();
    await database.close();
  });

  test('sync account config is stored as contextual NSSF', () async {
    final account = SyncAccountConfiguration(
      id: 'sync-1',
      providerType: 'webdav',
      configJson: '{"password":"sync-secret"}',
      lastSyncAt: DateTime(2026, 7, 16, 10),
      status: 'ready',
      createdAt: DateTime(2026, 7, 16, 9),
      updatedAt: DateTime(2026, 7, 16, 10),
    );

    await repository.saveSyncAccount(account);

    final rows = await database.run(
      (db) => db.query(
        DatabaseSchema.syncAccounts,
        where: 'id = ?',
        whereArgs: <Object>[account.id],
      ),
    );
    final encrypted = rows.single['encrypted_config']! as List<int>;
    expect(() => FieldEnvelopeCodec.decode(encrypted), returnsNormally);
    expect(
      utf8.decode(encrypted, allowMalformed: true),
      isNot(contains('sync-secret')),
    );

    final restored = await repository.loadSyncAccount(account.id);
    expect(restored?.configJson, account.configJson);
    expect(restored?.providerType, account.providerType);
    expect(restored?.status, account.status);
    expect(restored?.lastSyncAt, account.lastSyncAt);
  });

  test(
    'sync account config rejects row substitution and legacy bytes',
    () async {
      final account = SyncAccountConfiguration(
        id: 'sync-source',
        providerType: 'webdav',
        configJson: '{"token":"source-secret"}',
        lastSyncAt: null,
        status: 'ready',
        createdAt: DateTime(2026, 7, 16),
        updatedAt: DateTime(2026, 7, 16),
      );
      await repository.saveSyncAccount(account);
      await database.run((db) async {
        final source = (await db.query(
          DatabaseSchema.syncAccounts,
          where: 'id = ?',
          whereArgs: <Object>[account.id],
        )).single;

        await db.insert(DatabaseSchema.syncAccounts, <String, Object?>{
          ...source,
          'id': 'sync-substituted',
        });
        await db.insert(DatabaseSchema.syncAccounts, <String, Object?>{
          ...source,
          'id': 'sync-legacy',
          'encrypted_config': utf8.encode('{"token":"legacy"}'),
        });
      });

      await expectLater(
        repository.loadSyncAccount('sync-substituted'),
        _fieldFailure(FieldCryptoFailure.authenticationFailed),
      );
      await expectLater(
        repository.loadSyncAccount('sync-legacy'),
        _fieldFailure(FieldCryptoFailure.invalidEnvelope),
      );
    },
  );

  test('app setting is contextual NSSF and rejects invalid storage', () async {
    await repository.saveAppSetting(
      key: 'search.private_scope',
      value: '{"passwords":false}',
    );
    final source = await database.run((db) async {
      return (await db.query(
        DatabaseSchema.appSettings,
        where: 'key = ?',
        whereArgs: const <Object>['search.private_scope'],
      )).single;
    });
    final encrypted = source['value_ciphertext']! as List<int>;
    expect(() => FieldEnvelopeCodec.decode(encrypted), returnsNormally);
    expect(
      await repository.loadAppSetting('search.private_scope'),
      '{"passwords":false}',
    );

    await database.run((db) async {
      await db.insert(DatabaseSchema.appSettings, <String, Object?>{
        'key': 'search.substituted',
        'value_ciphertext': encrypted,
      });
      await db.insert(DatabaseSchema.appSettings, <String, Object?>{
        'key': 'search.legacy',
        'value_ciphertext': utf8.encode('legacy-value'),
      });
    });

    await expectLater(
      repository.loadAppSetting('search.substituted'),
      _fieldFailure(FieldCryptoFailure.authenticationFailed),
    );
    await expectLater(
      repository.loadAppSetting('search.legacy'),
      _fieldFailure(FieldCryptoFailure.invalidEnvelope),
    );
  });
}

Matcher _fieldFailure(FieldCryptoFailure failure) {
  return throwsA(
    isA<FieldCryptoException>().having(
      (error) => error.failure,
      'failure',
      failure,
    ),
  );
}
