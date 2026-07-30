part of 'native_security_bridge_test.dart';

void _registerNativeSecurityMigrationContractCases({
  required MethodChannel channel,
  required TestDefaultBinaryMessenger messenger,
}) {
  test('legacy migration methods use the dedicated channel contract', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'beginLegacyMigration':
          expect(call.arguments, <String, Object?>{'reason': '升级安全存储'});
          return <String, Object?>{
            'keyId': _validKeyId,
            'databaseKey': Uint8List(32),
            'fieldKey': Uint8List(32),
            'searchIndexFingerprintKey': Uint8List(32),
            'unlockMethod': 'system',
            'legacyDatabasePassword': Uint8List.fromList(
              utf8.encode('legacy-password'),
            ),
          };
        case 'getLegacyMigrationState':
          return _migrationStatePayload('detected');
        case 'prepareLegacyMigrationBackup':
        case 'prepareLegacyMigrationPending':
        case 'markLegacyMigrationRowsCopied':
        case 'markLegacyMigrationValidated':
        case 'activateLegacyMigration':
        case 'markLegacyMigrationPostSwapValidated':
        case 'cleanupLegacyMigrationFiles':
          expect(call.arguments, <String, Object?>{'keyId': _validKeyId});
          return _migrationStatePayload('cleanupComplete');
        case 'commitLegacyMigration':
          expect(call.arguments, <String, Object?>{
            'keyId': _validKeyId,
            'activeDigest': 'b' * 64,
          });
          return null;
        case 'finishLegacyMigration':
          expect(call.arguments, <String, Object?>{'keyId': _validKeyId});
          return null;
        case 'abortLegacyMigration':
          return null;
      }
      fail('Unexpected method: ${call.method}');
    });
    const bridge = MethodChannelNativeSecurityBridge();

    final material = await bridge.beginLegacyMigration();
    addTearDown(material.clear);
    final detected = await bridge.getLegacyMigrationState();
    await bridge.prepareLegacyMigrationBackup(_validKeyId);
    await bridge.prepareLegacyMigrationPending(_validKeyId);
    await bridge.markLegacyMigrationRowsCopied(_validKeyId);
    await bridge.markLegacyMigrationValidated(_validKeyId);
    await bridge.activateLegacyMigration(_validKeyId);
    await bridge.markLegacyMigrationPostSwapValidated(_validKeyId);
    await bridge.cleanupLegacyMigrationFiles(_validKeyId);
    await bridge.commitLegacyMigration(
      keyId: _validKeyId,
      activeDigest: 'b' * 64,
    );
    await bridge.finishLegacyMigration(_validKeyId);
    await bridge.abortLegacyMigration();

    expect(material.keyId, _validKeyId);
    expect(utf8.decode(material.legacyDatabasePassword!), 'legacy-password');
    expect(detected.stage, NativeLegacyMigrationStage.detected);
    expect(calls, <String>[
      'beginLegacyMigration',
      'getLegacyMigrationState',
      'prepareLegacyMigrationBackup',
      'prepareLegacyMigrationPending',
      'markLegacyMigrationRowsCopied',
      'markLegacyMigrationValidated',
      'activateLegacyMigration',
      'markLegacyMigrationPostSwapValidated',
      'cleanupLegacyMigrationFiles',
      'commitLegacyMigration',
      'finishLegacyMigration',
      'abortLegacyMigration',
    ]);
  });
}

void _registerNativeSecurityMigrationPathCases() {
  test('migration state rejects a pending path outside the migration root', () {
    final payload = _migrationStatePayload('pendingCreated')
      ..['pendingPath'] = r'E:\app\documents\note_secret_search.db';

    expect(
      () => parseNativeLegacyMigrationState(payload),
      throwsFormatException,
    );
  });

  test('migration state rejects path traversal', () {
    final payload = _migrationStatePayload('pendingCreated')
      ..['pendingPath'] =
          r'E:\app\no_backup\security\migration-v2\pending\..\..\victim.db';

    expect(
      () => parseNativeLegacyMigrationState(payload),
      throwsFormatException,
    );
  });

  test('migration state rejects an active database inside the workspace', () {
    final payload = _migrationStatePayload('pendingCreated')
      ..['activePath'] =
          r'E:\app\no_backup\security\migration-v2\active\note_secret_search.db';

    expect(
      () => parseNativeLegacyMigrationState(payload),
      throwsFormatException,
    );
  });

  test('migration state accepts the fixed Android migration layout', () {
    final state = parseNativeLegacyMigrationState(
      _migrationStatePayload('pendingCreated'),
    );

    expect(
      state.pendingPath,
      r'E:\app\no_backup\security\migration-v2\pending\note_secret_search.db',
    );
  });
}
