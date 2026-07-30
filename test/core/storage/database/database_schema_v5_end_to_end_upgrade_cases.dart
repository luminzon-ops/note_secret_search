part of 'database_schema_v5_end_to_end_test.dart';

void _registerDatabaseSchemaV5UpgradeCases() {
  for (final testCase in _migrationCases) {
    test(
      '${testCase.name} upgrades through frozen v4 into validated v8',
      () async {
        final fixture = await createPhase3DatabaseMigrationFixture(
          testCase.version,
        );
        addTearDown(fixture.dispose);
        await _expectLegacySource(fixture.sourcePath, testCase);

        final v4 = await databaseFactoryFfi.openDatabase(
          fixture.databasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        late final Map<String, String?> protectedBytes;
        late final String canonicalDigest;
        try {
          protectedBytes = await capturePhase3ProtectedBytes(v4);
          canonicalDigest = await phase3CanonicalDataDigest(v4, fixture.crypto);
          expect(canonicalDigest, testCase.expectedCanonicalDigest);
          await _expectPhase2State(v4, testCase);
        } finally {
          await v4.close();
        }

        final manager = DatabaseSchemaManager(
          nowMilliseconds: () => 1_800_000_000_000,
        );
        final v6 = await _openManagedDatabase(fixture.databasePath, manager);
        addTearDown(v6.close);

        await manager.validate(v6);
        await _expectBusinessData(
          v6,
          fixture: fixture,
          testCase: testCase,
          protectedBytes: protectedBytes,
          expectedCanonicalDigest: testCase.expectedV8CanonicalDigest,
        );
        await _expectSchemaGate(v6, manager);
      },
    );
  }
}
