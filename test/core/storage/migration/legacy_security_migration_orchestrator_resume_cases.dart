part of 'legacy_security_migration_orchestrator_test.dart';

void _registerLegacySecurityMigrationResumeCases() {
  test(
    'cleanup-complete resume finishes credentials without recopying',
    () async {
      final calls = <String>[];
      final bridge = _FakeMigrationBridge(
        calls,
        initialStage: NativeLegacyMigrationStage.cleanupComplete,
      );
      final keys = DatabaseSessionKeyStore();
      addTearDown(keys.clear);
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: bridge,
        securityBridge: _FakeSecurityBridge(calls),
        migrationRunner: _FakeMigrationRunner(calls),
        postSwapValidator: _FakePostSwapValidator(calls),
        legacyPinStore: _FakeLegacyPinStore(calls, pin: null),
        sessionKeyStore: keys,
      );

      await orchestrator.startOrResume();

      expect(calls, <String>[
        'state',
        'readPin',
        'clearPin',
        'commit',
        'finish',
      ]);
    },
  );

  for (final testCase
      in const <
        ({
          NativeLegacyMigrationStage stage,
          bool copies,
          bool activates,
          bool postValidates,
          bool cleansFiles,
        })
      >[
        (
          stage: NativeLegacyMigrationStage.backupReady,
          copies: true,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.pendingCreated,
          copies: true,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.rowsCopied,
          copies: true,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.validated,
          copies: false,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.oldMoved,
          copies: false,
          activates: true,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.newActivated,
          copies: false,
          activates: false,
          postValidates: true,
          cleansFiles: true,
        ),
        (
          stage: NativeLegacyMigrationStage.postSwapValidated,
          copies: false,
          activates: false,
          postValidates: false,
          cleansFiles: true,
        ),
      ]) {
    test('resumes safely from ${testCase.stage.name}', () async {
      final calls = <String>[];
      final bridge = _FakeMigrationBridge(calls, initialStage: testCase.stage);
      final keys = DatabaseSessionKeyStore();
      addTearDown(keys.clear);
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: bridge,
        securityBridge: _FakeSecurityBridge(calls),
        migrationRunner: _FakeMigrationRunner(calls),
        postSwapValidator: _FakePostSwapValidator(calls),
        legacyPinStore: _FakeLegacyPinStore(calls, pin: null),
        sessionKeyStore: keys,
      );

      await orchestrator.startOrResume();

      expect(calls.contains('copy'), testCase.copies);
      expect(calls.contains('activate'), testCase.activates);
      expect(calls.contains('postValidate'), testCase.postValidates);
      expect(calls.contains('cleanup'), testCase.cleansFiles);
      expect(
        calls,
        containsAllInOrder(<String>['readPin', 'clearPin', 'commit', 'finish']),
      );
      expect(keys.hasKeys, isFalse);
    });
  }

  test('legacy pin store accepts an already-cleared state', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final store = SharedPreferencesLegacyPinMigrationStore(
      loadPreferences: SharedPreferences.getInstance,
    );

    expect(
      await store.read(),
      isA<LegacyPinMigrationMaterial>()
          .having((value) => value.enabled, 'enabled', isFalse)
          .having((value) => value.pin, 'pin', isNull),
    );
    await store.clear();
  });

  test(
    'legacy pin store resumes cleanup while plaintext pin remains',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'security.pin_material': '2468',
        'security.pin_migration_cleanup_pending': true,
      });
      final store = SharedPreferencesLegacyPinMigrationStore(
        loadPreferences: SharedPreferences.getInstance,
      );

      final material = await store.read();

      expect(material.enabled, isTrue);
      expect(material.pin, '2468');
      await store.clear();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('security.pin_material'), isFalse);
      expect(
        preferences.containsKey('security.pin_migration_cleanup_pending'),
        isFalse,
      );
    },
  );

  test(
    'legacy pin store resumes cleanup after plaintext pin removal',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'security.pin_migration_cleanup_pending': true,
      });
      final store = SharedPreferencesLegacyPinMigrationStore(
        loadPreferences: SharedPreferences.getInstance,
      );

      final material = await store.read();

      expect(material.enabled, isFalse);
      expect(material.pin, isNull);
      await store.clear();
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey('security.pin_migration_cleanup_pending'),
        isFalse,
      );
    },
  );

  test('legacy pin store rejects inconsistent plaintext state', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'security.pin_enabled': true,
    });
    final store = SharedPreferencesLegacyPinMigrationStore(
      loadPreferences: SharedPreferences.getInstance,
    );

    await expectLater(store.read(), throwsStateError);
  });
}
