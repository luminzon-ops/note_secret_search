part of 'legacy_security_migration_orchestrator_test.dart';

void _registerLegacySecurityMigrationOrderCases() {
  test('runs migration and cleanup in recoverable order', () async {
    final calls = <String>[];
    final bridge = _FakeMigrationBridge(calls);
    final security = _FakeSecurityBridge(calls);
    final runner = _FakeMigrationRunner(calls);
    final validator = _FakePostSwapValidator(calls);
    final pinStore = _FakeLegacyPinStore(calls, pin: '2468');
    final keys = DatabaseSessionKeyStore();
    addTearDown(keys.clear);
    final orchestrator = LegacySecurityMigrationOrchestrator(
      migrationBridge: bridge,
      securityBridge: security,
      migrationRunner: runner,
      postSwapValidator: validator,
      legacyPinStore: pinStore,
      sessionKeyStore: keys,
    );

    await orchestrator.startOrResume();

    expect(calls, <String>[
      'state',
      'readPin',
      'begin',
      'state',
      'checkpoint',
      'backup',
      'pending',
      'copy',
      'rowsCopied',
      'validated',
      'activate',
      'postValidate',
      'postSwap',
      'cleanup',
      'configurePin:2468',
      'clearPin',
      'commit',
      'finish',
    ]);
    expect(runner.legacyPassword, 'legacy-password');
    expect(runner.databasePassword, List.filled(32, 1).map(_hex).join());
    expect(runner.sourcePath, '/fixed/backup.db');
    expect(runner.pendingPath, '/fixed/pending.db');
    expect(keys.hasKeys, isFalse);
    expect(bridge.material.databaseKey, everyElement(0));
    expect(bridge.material.fieldKey, everyElement(0));
    expect(bridge.material.legacyDatabasePassword, everyElement(0));
  });

  test(
    'copy failure aborts without deleting legacy credentials or pin',
    () async {
      final calls = <String>[];
      final bridge = _FakeMigrationBridge(calls);
      final runner = _FakeMigrationRunner(calls)..failure = StateError('copy');
      final keys = DatabaseSessionKeyStore();
      addTearDown(keys.clear);
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: bridge,
        securityBridge: _FakeSecurityBridge(calls),
        migrationRunner: runner,
        postSwapValidator: _FakePostSwapValidator(calls),
        legacyPinStore: _FakeLegacyPinStore(calls, pin: '2468'),
        sessionKeyStore: keys,
      );

      await expectLater(orchestrator.startOrResume(), throwsStateError);

      expect(calls, contains('abort'));
      expect(calls, containsAllInOrder(<String>['copy', 'pending', 'abort']));
      expect(calls.where((call) => call == 'pending'), hasLength(2));
      expect(calls, isNot(contains('commit')));
      expect(calls, isNot(contains('clearPin')));
      expect(calls, isNot(contains('finish')));
      expect(keys.hasKeys, isFalse);
      expect(bridge.material.databaseKey, everyElement(0));
      expect(bridge.material.fieldKey, everyElement(0));
    },
  );

  test(
    'post-swap validation failure restores the legacy database for retry',
    () async {
      final calls = <String>[];
      final bridge = _FakeMigrationBridge(
        calls,
        initialStage: NativeLegacyMigrationStage.newActivated,
      );
      final validator = _FakePostSwapValidator(calls)
        ..failure = StateError('post-swap');
      final keys = DatabaseSessionKeyStore();
      addTearDown(keys.clear);
      final orchestrator = LegacySecurityMigrationOrchestrator(
        migrationBridge: bridge,
        securityBridge: _FakeSecurityBridge(calls),
        migrationRunner: _FakeMigrationRunner(calls),
        postSwapValidator: validator,
        legacyPinStore: _FakeLegacyPinStore(calls, pin: null),
        sessionKeyStore: keys,
      );

      await expectLater(orchestrator.startOrResume(), throwsStateError);

      expect(
        calls,
        containsAllInOrder(<String>['postValidate', 'pending', 'abort']),
      );
      expect(calls, isNot(contains('cleanup')));
      expect(calls, isNot(contains('commit')));
      expect(calls, isNot(contains('finish')));
      expect(keys.hasKeys, isFalse);
    },
  );
}
