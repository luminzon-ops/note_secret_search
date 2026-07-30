part of 'native_security_bridge_test.dart';

void _registerNativeSecurityStateDecodeCases({
  required MethodChannel channel,
  required TestDefaultBinaryMessenger messenger,
}) {
  test('getSecurityState decodes a typed locked state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getSecurityState');
      return <String, Object?>{
        'status': 'locked',
        'keyId': _validKeyId,
        'pinConfigured': true,
        'deviceCredentialAvailable': true,
        'strongBiometricAvailable': false,
        'securityLevel': 'strongBox',
        'systemRebindRequired': true,
        'pinResetRequired': false,
      };
    });

    final state = await const MethodChannelNativeSecurityBridge()
        .getSecurityState();

    expect(state.status, NativeSecurityStatus.locked);
    expect(state.keyId, _validKeyId);
    expect(state.pinConfigured, isTrue);
    expect(state.deviceCredentialAvailable, isTrue);
    expect(state.strongBiometricAvailable, isFalse);
    expect(state.securityLevel, KeySecurityLevel.strongBox);
    expect(state.systemRebindRequired, isTrue);
    expect(state.pinResetRequired, isFalse);
  });

  test('getSecurityState accepts unprovisioned state without keyId', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getSecurityState');
      return _validStatePayload()
        ..['status'] = 'unprovisioned'
        ..remove('keyId');
    });

    final state = await const MethodChannelNativeSecurityBridge()
        .getSecurityState();

    expect(state.status, NativeSecurityStatus.unprovisioned);
    expect(state.keyId, isNull);
  });

  test(
    'getSecurityState accepts legacy migration state without keyId',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getSecurityState');
        return _validStatePayload()
          ..['status'] = 'legacyMigrationRequired'
          ..remove('keyId');
      });

      final state = await const MethodChannelNativeSecurityBridge()
          .getSecurityState();

      expect(state.status, NativeSecurityStatus.legacyMigrationRequired);
      expect(state.keyId, isNull);
    },
  );

  test('getSecurityState accepts recovery state without keyId', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getSecurityState');
      return _validStatePayload()
        ..['status'] = 'recoveryRequired'
        ..remove('keyId');
    });

    final state = await const MethodChannelNativeSecurityBridge()
        .getSecurityState();

    expect(state.status, NativeSecurityStatus.recoveryRequired);
    expect(state.keyId, isNull);
  });

  test('getSecurityState rejects missing keyId for locked state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validStatePayload()..remove('keyId');
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().getSecurityState(),
      throwsFormatException,
    );
  });

  test('getSecurityState rejects blank keyId', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validStatePayload()..['keyId'] = '   ';
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().getSecurityState(),
      throwsFormatException,
    );
  });

  test('getSecurityState rejects non-canonical keyId', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validStatePayload()..['keyId'] = 'key-v2';
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().getSecurityState(),
      throwsFormatException,
    );
  });

  test('getSecurityState rejects unknown status', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validStatePayload()..['status'] = 'ready';
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().getSecurityState(),
      throwsFormatException,
    );
  });

  test('getSecurityState rejects unknown security level', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validStatePayload()..['securityLevel'] = 'hardware';
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().getSecurityState(),
      throwsFormatException,
    );
  });

  test('provisionWithSystemAuth decodes and clears session keys', () async {
    final databaseKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final fieldKey = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
    final fingerprintKey = Uint8List.fromList(List<int>.filled(32, 0x5a));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'provisionWithSystemAuth');
      expect(call.arguments, <String, Object?>{'reason': '启用安全存储'});
      return <String, Object?>{
        'keyId': _validKeyId,
        'databaseKey': databaseKey,
        'fieldKey': fieldKey,
        'searchIndexFingerprintKey': fingerprintKey,
        'unlockMethod': 'system',
      };
    });

    final result = await const MethodChannelNativeSecurityBridge()
        .provisionWithSystemAuth();

    expect(result.keyId, _validKeyId);
    expect(result.databaseKey, orderedEquals(databaseKey));
    expect(result.fieldKey, orderedEquals(fieldKey));
    expect(result.searchIndexFingerprintKey, orderedEquals(fingerprintKey));
    expect(result.unlockMethod, 'system');
    expect(result.isCleared, isFalse);

    result.clear();
    result.clear();

    expect(result.isCleared, isTrue);
    expect(result.databaseKey, everyElement(0));
    expect(result.fieldKey, everyElement(0));
    expect(result.searchIndexFingerprintKey, everyElement(0));
    expect(databaseKey, isNot(everyElement(0)));
    expect(fieldKey, isNot(everyElement(0)));
    expect(fingerprintKey, isNot(everyElement(0)));

    result.databaseKey[0] = 7;
    result.fieldKey[0] = 9;
    result.clear();

    expect(result.databaseKey, everyElement(0));
    expect(result.fieldKey, everyElement(0));
  });
}
