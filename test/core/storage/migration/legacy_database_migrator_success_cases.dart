part of 'legacy_database_migrator_test.dart';

void _registerLegacyDatabaseMigratorSuccessCases() {
  test(
    'migrates a v1 database into a validated schema-v4 pending file',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.v1,
      );
      addTearDown(fixture.dispose);
      final keys = DatabaseSessionKeys(
        databaseKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
        fieldKey: Uint8List.fromList(List<int>.generate(32, (i) => 0x80 + i)),
      );
      addTearDown(keys.clear);
      final keyStore = DatabaseSessionKeyStore()..replace(keys);
      final crypto = AesGcmFieldCrypto(sessionKeyStore: keyStore);
      final migrator = LegacyDatabaseMigrator(
        databaseFactory: const _FfiMigrationDatabaseFactory(),
        cryptoService: crypto,
        now: () => DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000),
      );

      final result = await migrator.migrate(
        sourcePath: fixture.sourcePath,
        pendingPath: fixture.pendingPath,
        legacyPassword: 'legacy-password',
        databasePassword: 'new-database-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      );

      expect(result.sourceSchemaVersion, 1);
      expect(result.targetSchemaVersion, 4);
      expect(result.quickCheck, 'ok');
      expect(result.preservedRowCounts, containsPair('secret_items', 2));
      expect(result.preservedRowCounts, containsPair('note_items', 2));
      expect(result.preservedRowCounts, containsPair('model_registry', 1));
      expect(result.preservedRowCounts, containsPair('chat_sessions', 0));

      final target = await databaseFactoryFfi.openDatabase(fixture.pendingPath);
      addTearDown(target.close);
      expect(
        (await target.rawQuery('PRAGMA user_version')).single['user_version'],
        4,
      );
      expect(await _count(target, 'embedding_chunks'), 0);
      expect(await _count(target, 'download_tasks'), 0);
      expect(await _count(target, 'model_catalog_entries'), 0);
      expect(await _count(target, 'secret_items'), 2);
      expect(await _count(target, 'note_items'), 2);

      final metadata = (await target.query('security_metadata')).single;
      expect(metadata['key_id'], '123e4567-e89b-42d3-a456-426614174000');
      expect(metadata['source_schema_version'], 1);
      expect(metadata['field_envelope_version'], 1);
      expect(metadata['migration_state'], 'validated');

      await _expectEncryptedFields(target, crypto, fixture.expectedPlaintext);

      final deletedSecret = (await target.query(
        'secret_items',
        where: 'id = ?',
        whereArgs: const <Object>['secret-deleted'],
      )).single;
      expect(deletedSecret['deleted_at'], isNotNull);
      final deletedNote = (await target.query(
        'note_items',
        where: 'id = ?',
        whereArgs: const <Object>['note-deleted'],
      )).single;
      expect(deletedNote['deleted_at'], isNotNull);

      final model = (await target.query('model_registry')).single;
      expect(model['integrity_status'], 'unknown');
      expect(model['artifact_paths_json'], isNull);

      final providerPlaintext = crypto.decryptField(
        (await target.query('provider_configs')).single['encrypted_config']
            as List<int>,
        field: EncryptedDatabaseField.providerConfig,
        rowId: 'provider-1',
      );
      expect(jsonDecode(providerPlaintext), isA<Map<String, Object?>>());
    },
  );

  for (final testCase
      in const <
        ({
          LegacyFixtureVersion version,
          String name,
          int schemaVersion,
          String? artifactPaths,
          String integrityStatus,
        })
      >[
        (
          version: LegacyFixtureVersion.v2,
          name: 'v2',
          schemaVersion: 2,
          artifactPaths: null,
          integrityStatus: 'unknown',
        ),
        (
          version: LegacyFixtureVersion.upgradedV3,
          name: 'an upgraded v3',
          schemaVersion: 3,
          artifactPaths: '["/models/legacy.onnx"]',
          integrityStatus: 'unknown',
        ),
        (
          version: LegacyFixtureVersion.freshV3,
          name: 'a fresh v3',
          schemaVersion: 3,
          artifactPaths: '["/models/legacy.onnx"]',
          integrityStatus: 'verified',
        ),
      ]) {
    test(
      'migrates ${testCase.name} database without losing compatible rows',
      () async {
        final fixture = await createLegacyDatabaseFixture(testCase.version);
        addTearDown(fixture.dispose);
        final harness = _MigrationHarness();
        addTearDown(harness.dispose);

        final result = await harness.migrator.migrate(
          sourcePath: fixture.sourcePath,
          pendingPath: fixture.pendingPath,
          legacyPassword: 'legacy-password',
          databasePassword: 'new-database-password',
          keyId: '123e4567-e89b-42d3-a456-426614174000',
        );

        expect(result.sourceSchemaVersion, testCase.schemaVersion);
        expect(result.preservedRowCounts['chat_sessions'], 1);
        expect(result.preservedRowCounts['chat_messages'], 1);

        final target = await databaseFactoryFfi.openDatabase(
          fixture.pendingPath,
        );
        addTearDown(target.close);
        expect(await _count(target, 'chat_sessions'), 1);
        expect(await _count(target, 'chat_messages'), 1);
        expect(await _count(target, 'embedding_chunks'), 0);
        final model = (await target.query('model_registry')).single;
        expect(model['artifact_paths_json'], testCase.artifactPaths);
        expect(model['integrity_status'], testCase.integrityStatus);
        await _expectEncryptedFields(
          target,
          harness.crypto,
          fixture.expectedPlaintext,
        );
      },
    );
  }
}
