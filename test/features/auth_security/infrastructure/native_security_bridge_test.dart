import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/database_key_provider.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/platform_secure_gateways.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('note_secret_search/native_security');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('native security bridge rejects null database password material', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getDatabasePasswordMaterial');
      return null;
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().getDatabasePasswordMaterial(),
      throwsA(isA<StateError>()),
    );
  });

  test('native security bridge rejects blank database password material', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getDatabasePasswordMaterial');
      return '   ';
    });

    await expectLater(
      const MethodChannelNativeSecurityBridge().getDatabasePasswordMaterial(),
      throwsA(isA<StateError>()),
    );
  });

  test('database key provider rejects blank gateway material', () async {
    final provider = NativeDatabaseKeyProvider(
      secureKeyGateway: _StaticSecureKeyGateway('  '),
    );

    await expectLater(
      provider.getDatabasePassword(),
      throwsA(isA<StateError>()),
    );
  });

  test('database key provider returns trimmed valid material', () async {
    final provider = NativeDatabaseKeyProvider(
      secureKeyGateway: _StaticSecureKeyGateway(' valid-material '),
    );

    expect(await provider.getDatabasePassword(), 'valid-material');
  });
}

class _StaticSecureKeyGateway implements SecureKeyGateway {
  _StaticSecureKeyGateway(this.material);

  final String material;

  @override
  Future<void> ensureRootKey() async {}

  @override
  Future<String> getDatabasePasswordMaterial() async => material;
}
