part of 'native_security_bridge_test.dart';

void _registerNativeSecurityOperationCases({
  required MethodChannel channel,
  required TestDefaultBinaryMessenger messenger,
}) {
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
}

void _registerNativeSecurityExceptionMappingCases({
  required MethodChannel channel,
  required TestDefaultBinaryMessenger messenger,
}) {
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
