import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_models/infrastructure/device_profiler_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/device_profiler');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'maps complete device facts and derives legacy displays in Dart',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getProfile');
        return <String, Object?>{
          'manufacturer': 'Huawei',
          'brand': 'HUAWEI',
          'model': 'SPN-AL00',
          'device': 'HWSPN',
          'product': 'SPN-AL00',
          'sdkInt': 29,
          'release': '10',
          'supportedAbis': <String>[
            'arm64-v8a',
            'armeabi-v7a',
            'x86_64',
            'x86',
          ],
          'cpuAbi': 'arm64-v8a',
          'totalRamMb': 8192,
          'availableRamMb': 4096,
          'totalStorageMb': 128000,
          'availableStorageMb': 64000,
          'tier': 'low',
          'ready': true,
          'enabled': true,
        };
      });

      final profile = await DeviceProfilerBridge(channel: channel).getProfile();

      expect(profile, isNotNull);
      expect(profile!.manufacturer, 'Huawei');
      expect(profile.brand, 'HUAWEI');
      expect(profile.model, 'SPN-AL00');
      expect(profile.device, 'HWSPN');
      expect(profile.product, 'SPN-AL00');
      expect(profile.sdkInt, 29);
      expect(profile.release, '10');
      expect(profile.supportedAbis, <String>[
        'arm64-v8a',
        'armeabi-v7a',
        'x86_64',
        'x86',
      ]);
      expect(profile.cpuAbi, 'arm64-v8a');
      expect(profile.cpuDisplay, 'arm64-v8a, armeabi-v7a, x86_64, x86');
      expect(profile.totalRamMb, 8192);
      expect(profile.availableRamMb, 4096);
      expect(profile.totalStorageMb, 128000);
      expect(profile.availableStorageMb, 64000);
      expect(profile.tier, 'high');
    },
  );

  test('returns no profile when native collection reports failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'PROFILE_UNAVAILABLE',
        message: '/private/device/profile/details',
      );
    });

    final profile = await DeviceProfilerBridge(channel: channel).getProfile();

    expect(profile, isNull);
  });
}
