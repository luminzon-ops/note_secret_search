part of 'legacy_database_migrator_test.dart';

void _registerLegacyDatabaseMigratorRejectionCases() {
  test('rejects invalid legacy UTF-8 for native pending cleanup', () async {
    final fixture = await createLegacyDatabaseFixture(LegacyFixtureVersion.v1);
    addTearDown(fixture.dispose);
    final source = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
    await source.update(
      'secret_items',
      <String, Object?>{
        'password_ciphertext': Uint8List.fromList(const <int>[0xff]),
      },
      where: 'id = ?',
      whereArgs: const <Object>['secret-1'],
    );
    await source.close();
    final harness = _MigrationHarness();
    addTearDown(harness.dispose);

    await expectLater(
      harness.migrator.migrate(
        sourcePath: fixture.sourcePath,
        pendingPath: fixture.pendingPath,
        legacyPassword: 'legacy-password',
        databasePassword: 'new-database-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsFormatException,
    );

    expect(File(fixture.pendingPath).existsSync(), isTrue);
  });

  test(
    'rejects changed migrated plaintext for native pending cleanup',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.v1,
      );
      addTearDown(fixture.dispose);
      final harness = _MigrationHarness(corruptNoteContent: true);
      addTearDown(harness.dispose);

      await expectLater(
        harness.migrator.migrate(
          sourcePath: fixture.sourcePath,
          pendingPath: fixture.pendingPath,
          legacyPassword: 'legacy-password',
          databasePassword: 'new-database-password',
          keyId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsStateError,
      );

      expect(File(fixture.pendingPath).existsSync(), isTrue);
    },
  );

  test('rejects changed non-secret data for native pending cleanup', () async {
    final fixture = await createLegacyDatabaseFixture(LegacyFixtureVersion.v1);
    addTearDown(fixture.dispose);
    final harness = _MigrationHarness(
      databaseFactory: const _NonSecretCorruptingMigrationDatabaseFactory(),
    );
    addTearDown(harness.dispose);

    await expectLater(
      harness.migrator.migrate(
        sourcePath: fixture.sourcePath,
        pendingPath: fixture.pendingPath,
        legacyPassword: 'legacy-password',
        databasePassword: 'new-database-password',
        keyId: '123e4567-e89b-42d3-a456-426614174000',
      ),
      throwsStateError,
    );

    expect(File(fixture.pendingPath).existsSync(), isTrue);
  });

  test(
    'rejects a non-legacy source before touching existing pending data',
    () async {
      final fixture = await createLegacyDatabaseFixture(
        LegacyFixtureVersion.v1,
      );
      addTearDown(fixture.dispose);
      final source = await databaseFactoryFfi.openDatabase(fixture.sourcePath);
      await source.execute('PRAGMA user_version = 4');
      await source.close();
      final pending = File(fixture.pendingPath);
      final sentinel = Uint8List.fromList(const <int>[9, 8, 7, 6]);
      await pending.writeAsBytes(sentinel, flush: true);
      final harness = _MigrationHarness();
      addTearDown(harness.dispose);

      await expectLater(
        harness.migrator.migrate(
          sourcePath: fixture.sourcePath,
          pendingPath: fixture.pendingPath,
          legacyPassword: 'legacy-password',
          databasePassword: 'new-database-password',
          keyId: '123e4567-e89b-42d3-a456-426614174000',
        ),
        throwsA(
          isA<LegacyDatabaseMigrationException>().having(
            (error) => error.failure,
            'failure',
            LegacyDatabaseMigrationFailure.unsupportedSourceVersion,
          ),
        ),
      );

      expect(await pending.readAsBytes(), orderedEquals(sentinel));
    },
  );
}
