part of 'native_security_bridge_test.dart';

void _registerNativeSecurityUnlockDecodeCases({
  required MethodChannel channel,
  required TestDefaultBinaryMessenger messenger,
}) {
  test('NativeUnlockResult takes ownership of decoder key arrays', () {
    final databaseKey = Uint8List.fromList(List<int>.filled(32, 7));
    final fieldKey = Uint8List.fromList(List<int>.filled(32, 9));
    final fingerprintKey = Uint8List.fromList(List<int>.filled(32, 11));
    final result = NativeUnlockResult(
      keyId: _validKeyId,
      databaseKey: databaseKey,
      fieldKey: fieldKey,
      searchIndexFingerprintKey: fingerprintKey,
      unlockMethod: 'system',
    );

    result.clear();

    expect(databaseKey, everyElement(0));
    expect(fieldKey, everyElement(0));
    expect(fingerprintKey, everyElement(0));
  });

  test('unlockWithSystemAuth decodes typed key material', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'unlockWithSystemAuth');
      expect(call.arguments, <String, Object?>{'reason': '重新验证身份'});
      return <String, Object?>{
        'keyId': _validKeyId,
        'databaseKey': Uint8List(32),
        'fieldKey': Uint8List(32),
        'searchIndexFingerprintKey': Uint8List(32),
        'unlockMethod': 'system',
      };
    });

    final result = await const MethodChannelNativeSecurityBridge()
        .unlockWithSystemAuth(reason: '重新验证身份');
    addTearDown(result.clear);

    expect(result.keyId, _validKeyId);
    expect(result.databaseKey, hasLength(32));
    expect(result.fieldKey, hasLength(32));
    expect(result.searchIndexFingerprintKey, hasLength(32));
    expect(result.unlockMethod, 'system');
  });

  test(
    'configurePin sends temporary bytes and clears them after use',
    () async {
      Uint8List? transmittedPin;
      Uint8List? capturedPin;
      final bridge = MethodChannelNativeSecurityBridge(
        invoker: _CallbackNativeSecurityMethodInvoker((
          method,
          arguments,
        ) async {
          expect(method, 'configurePin');
          final payload = arguments as Map<Object?, Object?>;
          expect(payload['reason'], '配置备用 PIN');
          transmittedPin = payload['pin'] as Uint8List;
          capturedPin = Uint8List.fromList(transmittedPin!);
          return null;
        }),
      );

      await bridge.configurePin(pin: '2468', reason: '配置备用 PIN');

      expect(capturedPin, orderedEquals('2468'.codeUnits));
      expect(transmittedPin, everyElement(0));
    },
  );

  test('unlockWithPin decodes pin material and clears temporary pin', () async {
    Uint8List? transmittedPin;
    final bridge = MethodChannelNativeSecurityBridge(
      invoker: _CallbackNativeSecurityMethodInvoker((method, arguments) async {
        expect(method, 'unlockWithPin');
        final payload = arguments as Map<Object?, Object?>;
        transmittedPin = payload['pin'] as Uint8List;
        return _validUnlockPayload()..['unlockMethod'] = 'pin';
      }),
    );

    final result = await bridge.unlockWithPin(pin: '2468');
    addTearDown(result.clear);

    expect(result.unlockMethod, 'pin');
    expect(transmittedPin, everyElement(0));
  });

  test('unlockWithPin clears temporary pin when native call fails', () async {
    Uint8List? transmittedPin;
    final bridge = MethodChannelNativeSecurityBridge(
      invoker: _CallbackNativeSecurityMethodInvoker((method, arguments) async {
        final payload = arguments as Map<Object?, Object?>;
        transmittedPin = payload['pin'] as Uint8List;
        throw PlatformException(code: 'PIN_INCORRECT');
      }),
    );

    await expectLater(
      bridge.unlockWithPin(pin: '0000'),
      throwsA(
        isA<NativeSecurityException>().having(
          (error) => error.code,
          'code',
          'PIN_INCORRECT',
        ),
      ),
    );

    expect(transmittedPin, everyElement(0));
  });

  test(
    'rebindSystemAuthWithPin forwards and clears temporary pin bytes',
    () async {
      Uint8List? transmittedPin;
      Uint8List? capturedPin;
      final bridge = MethodChannelNativeSecurityBridge(
        invoker: _CallbackNativeSecurityMethodInvoker((
          method,
          arguments,
        ) async {
          expect(method, 'rebindSystemAuthWithPin');
          final payload = arguments as Map<Object?, Object?>;
          expect(payload['reason'], '恢复系统认证');
          transmittedPin = payload['pin'] as Uint8List;
          capturedPin = Uint8List.fromList(transmittedPin!);
          return null;
        }),
      );

      await bridge.rebindSystemAuthWithPin(pin: '2468', reason: '恢复系统认证');

      expect(capturedPin, orderedEquals('2468'.codeUnits));
      expect(transmittedPin, everyElement(0));
    },
  );

  test('removePin forwards its authenticated reason', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'removePin');
      expect(call.arguments, <String, Object?>{'reason': '移除备用 PIN'});
      return null;
    });

    await const MethodChannelNativeSecurityBridge().removePin(
      reason: '移除备用 PIN',
    );
  });

  test('system and pin calls reject a mismatched unlock method', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validUnlockPayload()
        ..['unlockMethod'] = call.method == 'unlockWithPin' ? 'system' : 'pin';
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().unlockWithSystemAuth(),
      throwsFormatException,
    );
    await expectLater(
      const MethodChannelNativeSecurityBridge().unlockWithPin(pin: '2468'),
      throwsFormatException,
    );
  });

  test('unlock result rejects missing and blank keyId', () async {
    for (final keyId in <Object?>[null, '   ']) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        final payload = _validUnlockPayload();
        if (keyId == null) {
          payload.remove('keyId');
        } else {
          payload['keyId'] = keyId;
        }
        return payload;
      });

      await expectLater(
        const MethodChannelNativeSecurityBridge().unlockWithSystemAuth(),
        throwsFormatException,
      );
    }
  });

  test('unlock result requires a search index fingerprint key', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validUnlockPayload()..remove('searchIndexFingerprintKey');
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().unlockWithSystemAuth(),
      throwsFormatException,
    );
  });

  test('invalid unlock metadata clears received key arrays', () {
    final databaseKey = Uint8List.fromList(List<int>.filled(32, 7));
    final fieldKey = Uint8List.fromList(List<int>.filled(32, 9));
    final fingerprintKey = Uint8List.fromList(List<int>.filled(32, 11));
    final payload = <String, Object?>{
      'keyId': 'invalid-key-id',
      'databaseKey': databaseKey,
      'fieldKey': fieldKey,
      'searchIndexFingerprintKey': fingerprintKey,
      'unlockMethod': 'system',
    };

    expect(() => parseNativeUnlockResult(payload), throwsFormatException);

    expect(databaseKey, everyElement(0));
    expect(fieldKey, everyElement(0));
    expect(fingerprintKey, everyElement(0));
  });

  test('unlock result rejects non-Uint8List key material', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validUnlockPayload()..['databaseKey'] = List<int>.filled(32, 0);
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().unlockWithSystemAuth(),
      throwsFormatException,
    );
  });

  test('unlock result rejects key material with wrong lengths', () async {
    for (final field in <String>[
      'databaseKey',
      'fieldKey',
      'searchIndexFingerprintKey',
    ]) {
      for (final length in <int>[31, 33]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          return _validUnlockPayload()..[field] = Uint8List(length);
        });

        await expectLater(
          const MethodChannelNativeSecurityBridge().unlockWithSystemAuth(),
          throwsFormatException,
        );
      }
    }
  });

  test('unlock result rejects unknown unlock method', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return _validUnlockPayload()..['unlockMethod'] = 'password';
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().unlockWithSystemAuth(),
      throwsFormatException,
    );
  });
}
