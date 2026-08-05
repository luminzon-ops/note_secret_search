import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_secret_search/core/security/secure_clipboard.dart';
import 'package:note_secret_search/features/settings/application/security_settings_providers.dart';

final secureClipboardGatewayProvider = Provider<SecureClipboardGateway>((ref) {
  return const PlatformSecureClipboardGateway();
});

final secureClipboardControllerProvider = Provider<SecureClipboardController>((
  ref,
) {
  final controller = SecureClipboardController(
    gateway: ref.watch(secureClipboardGatewayProvider),
    loadClearSeconds: () async {
      final settings = await ref
          .read(securitySettingsRepositoryProvider)
          .load();
      return settings.clipboardClearSeconds;
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});

class PlatformSecureClipboardGateway implements SecureClipboardGateway {
  const PlatformSecureClipboardGateway();

  @override
  Future<String?> getText() async {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }

  @override
  Future<void> setText(String value) {
    return Clipboard.setData(ClipboardData(text: value));
  }
}
