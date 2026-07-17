import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/app/di/bootstrap_provider.dart';
import 'package:note_secret_search/features/auth_security/infrastructure/native_security_bridge.dart';

void main() {
  test(
    'locking the session cancels the active native security operation',
    () async {
      final bridge = _RecordingNativeSecurityBridge();
      final container = ProviderContainer(
        overrides: [nativeSecurityBridgeProvider.overrideWithValue(bridge)],
      );
      addTearDown(container.dispose);

      container.read(lockSessionControllerProvider.notifier).lock();
      await Future<void>.delayed(Duration.zero);

      expect(bridge.lockCalls, 1);
    },
  );
}

class _RecordingNativeSecurityBridge implements NativeSecurityBridge {
  int lockCalls = 0;

  @override
  Future<void> lock() async {
    lockCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
