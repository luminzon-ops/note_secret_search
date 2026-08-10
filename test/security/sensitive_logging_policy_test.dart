import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production sources do not restore the fixed database key fallback', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/note_secret_search/'
      'SecureKeyManager.kt',
    ).readAsStringSync();

    expect(source, isNot(contains('fallback-db-password-material')));
  });

  test('Dart logs omit sensitive paths and raw exceptions', () {
    final source = _readSources([
      'lib/core/logging/app_logger.dart',
      'lib/core/storage/database/sqlcipher_database.dart',
      'lib/features/ai_chat/application/ai_chat_conversation_controller.dart',
      'lib/features/ai_models/application/model_download_providers.dart',
      'lib/features/ai_models/infrastructure/model_download_service.dart',
      'lib/features/ai_models/infrastructure/model_source_probe_service.dart',
      'lib/features/auth_security/application/app_bootstrap_service.dart',
      'lib/features/auth_security/application/security_orchestrator.dart',
    ]);

    for (final forbidden in [
      'Bootstrapping application',
      'Initialized SQLCipher database at \$path',
      'Downloaded model \$modelId to \${targetFile.path}',
      'Deleted local model file at \$path',
      'Biometric availability:',
      ': \$error',
      'error: error',
      'stackTrace: stackTrace',
      '[ai_chat_send]',
      'correlation_id=',
      'session_id=',
      'message_id=',
      'input_len=',
      'sqlcipher_batch_executed statement_count=',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test(
    'Android runtime logs omit paths, prompts, device data, and raw errors',
    () {
      final source = _readSources([
        'android/app/src/main/kotlin/com/example/note_secret_search/'
            'DeviceProfilerPlugin.kt',
        'android/app/src/main/kotlin/com/example/note_secret_search/'
            'GgufLlamaCppBackend.kt',
        'android/app/src/main/kotlin/com/example/note_secret_search/'
            'LlamaContextAdapter.kt',
        'android/app/src/main/kotlin/com/example/note_secret_search/'
            'LlmRuntimePlugin.kt',
        'android/app/src/main/kotlin/com/example/note_secret_search/'
            'LocalLlmRuntime.kt',
        'android/app/src/main/kotlin/com/example/note_secret_search/'
            'NativeSecurityPlugin.kt',
        'android/app/src/main/kotlin/com/example/note_secret_search/'
            'SecureKeyManager.kt',
      ]);

      for (final forbidden in [
        'android.util.Log',
        'Log.',
        'path=\$modelPath',
        'mmproj=\$mmprojPath',
        'image=\$imagePath',
        'prompt=\$prompt',
        'usedPrivateContext=',
        'device fingerprint',
        'profile manufacturer=',
        'error=\${error.message}',
        'message=\${event.message}',
        'Log.e(TAG, message, error)',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    },
  );

  test('GGUF runtime bypasses helper path loading', () {
    final source = _readSources([
      'android/app/src/main/kotlin/com/example/note_secret_search/'
          'GgufLlamaCppBackend.kt',
      'android/app/src/main/kotlin/com/example/note_secret_search/'
          'LlamaContextAdapter.kt',
    ]);

    expect(source, isNot(contains('LlamaHelper')));
    expect(source, isNot(contains('org.nehuatl.llamacpp.LlamaContext')));
    expect(source, isNot(contains('RNLlamaContext')));
    expect(source, isNot(contains('normalizeModelPathForLlama')));
    expect(source, contains('LlamaContext'));
    expect(source, contains('model_fd'));
  });
}

String _readSources(List<String> paths) {
  return paths.map((path) => File(path).readAsStringSync()).join('\n');
}
