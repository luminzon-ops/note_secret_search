import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/auth_security/domain/security_models.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('note_secret_search/native_security');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

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

  test('lock invokes the native lock operation', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'lock');
      expect(call.arguments, isNull);
      return null;
    });

    await const MethodChannelNativeSecurityBridge().lock();
  });

  test('enableScreenshotProtection keeps its native method contract', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'enableScreenshotProtection');
      expect(call.arguments, isNull);
      return null;
    });

    await const MethodChannelNativeSecurityBridge()
        .enableScreenshotProtection();
  });

  test('updateRecentTaskProtection forwards obscured state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'updateRecentTaskProtection');
      expect(call.arguments, <String, Object?>{'obscured': true});
      return null;
    });

    await const MethodChannelNativeSecurityBridge().updateRecentTaskProtection(
      obscured: true,
    );
  });

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

  test('PlatformException is mapped to NativeSecurityException', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'AUTH_CANCELLED',
        message: 'Authentication was canceled.',
        details: <String, Object?>{'retryable': true},
      );
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().unlockWithSystemAuth(),
      throwsA(
        isA<NativeSecurityException>()
            .having((error) => error.code, 'code', 'AUTH_CANCELLED')
            .having(
              (error) => error.message,
              'message',
              'Authentication was canceled.',
            )
            .having((error) => error.details, 'details', <String, Object?>{
              'retryable': true,
            }),
      ),
    );
  });
}

Map<String, Object?> _migrationStatePayload(String stage) {
  final detected = stage == 'detected';
  return <String, Object?>{
    'stage': stage,
    'keyId': detected ? null : _validKeyId,
    'sourcePath':
        r'E:\app\no_backup\security\migration-v2\backup\note_secret_search.db',
    'pendingPath':
        r'E:\app\no_backup\security\migration-v2\pending\note_secret_search.db',
    'activePath': r'E:\app\databases\note_secret_search.db',
    'sourceDigest': detected ? null : 'a' * 64,
    'pendingDigest': detected ? null : 'b' * 64,
    'activeDigest': detected ? null : 'b' * 64,
  };
}

class _CallbackNativeSecurityMethodInvoker
    implements NativeSecurityMethodInvoker {
  _CallbackNativeSecurityMethodInvoker(this.callback);

  final Future<Object?> Function(String method, Object? arguments) callback;

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) {
    return callback(method, arguments);
  }
}

Map<String, Object?> _validStatePayload() {
  return <String, Object?>{
    'status': 'locked',
    'keyId': _validKeyId,
    'pinConfigured': false,
    'deviceCredentialAvailable': true,
    'strongBiometricAvailable': true,
    'securityLevel': 'tee',
    'systemRebindRequired': false,
    'pinResetRequired': false,
  };
}

Map<String, Object?> _validUnlockPayload() {
  return <String, Object?>{
    'keyId': _validKeyId,
    'databaseKey': Uint8List(32),
    'fieldKey': Uint8List(32),
    'searchIndexFingerprintKey': Uint8List(32),
    'unlockMethod': 'system',
  };
}

const _validKeyId = '123e4567-e89b-42d3-a456-426614174000';
