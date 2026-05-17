import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_runtime_status.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/local_llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/llm_runtime_bridge.dart';

void main() {
  group('mapLlmRuntimeState', () {
    test('maps ready runtime payload into LlmRuntimeState', () {
      const payload = <String, dynamic>{
        'ready': true,
        'reason': 'Local LLM model is ready.',
        'status': 'ready',
        'modelPath': '/data/user/0/app/files/models/phi.gguf',
        'checkedAt': 1714000000000,
      };

      final result = mapLlmRuntimeState(payload);

      expect(result.ready, isTrue);
      expect(result.reason, 'Local LLM model is ready.');
      expect(result.status, LlmRuntimeStatus.ready);
      expect(result.modelPath, '/data/user/0/app/files/models/phi.gguf');
      expect(result.checkedAt, DateTime.fromMillisecondsSinceEpoch(1714000000000));
    });

    test('maps degraded runtime payload into non-ready state', () {
      const payload = <String, dynamic>{
        'ready': false,
        'reason': 'Runtime probe failed.',
        'status': 'degraded',
        'modelPath': '/data/user/0/app/files/models/phi.gguf',
      };

      final result = mapLlmRuntimeState(payload);

      expect(result.ready, isFalse);
      expect(result.reason, 'Runtime probe failed.');
      expect(result.status, LlmRuntimeStatus.degraded);
      expect(result.modelPath, '/data/user/0/app/files/models/phi.gguf');
      expect(result.checkedAt, isNull);
    });

    test('maps installed_unverified runtime payload into non-ready state', () {
      const payload = <String, dynamic>{
        'ready': false,
        'reason': '检测到模型文件，但当前 backend 尚未完成真实校验。',
        'status': 'installed_unverified',
        'modelPath': '/data/user/0/app/files/models/phi.gguf',
        'checkedAt': 1714100000000,
      };

      final result = mapLlmRuntimeState(payload);

      expect(result.ready, isFalse);
      expect(result.status, LlmRuntimeStatus.installedUnverified);
      expect(result.reason, '检测到模型文件，但当前 backend 尚未完成真实校验。');
      expect(result.modelPath, '/data/user/0/app/files/models/phi.gguf');
      expect(result.checkedAt, DateTime.fromMillisecondsSinceEpoch(1714100000000));
    });

    test('maps probe-failed degraded payload into non-ready state', () {
      const payload = <String, dynamic>{
        'ready': false,
        'reason': '本地 LLM readiness probe 失败：backend returned empty text.',
        'status': 'degraded',
        'modelPath': '/data/user/0/app/files/models/phi.gguf',
        'checkedAt': 1714200000000,
      };

      final result = mapLlmRuntimeState(payload);

      expect(result.ready, isFalse);
      expect(result.status, LlmRuntimeStatus.degraded);
      expect(result.reason, contains('probe 失败'));
      expect(result.checkedAt, DateTime.fromMillisecondsSinceEpoch(1714200000000));
    });
  });

  group('MethodChannelLlmRuntimeBridge', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('maps generateText payload into LlmInferenceResponse-compatible map', () async {
      const channelName = 'note_secret_search/llm_runtime';
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const methodChannel = MethodChannel(channelName);

      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        expect(call.method, 'generateText');
        expect(call.arguments, <String, Object?>{
          'modelId': 'phi-mini',
          'modelPath': '/data/user/0/app/files/models/phi.gguf',
          'prompt': '你好',
          'usedPrivateContext': false,
          'maxOutputTokens': 96,
          'maxPromptChars': 1200,
          'contextLength': 1024,
          'conservativeMode': true,
          'temperature': 0.7,
          'topK': 40,
          'topP': 0.9,
          'seed': 42,
          'stopSequences': <String>['</s>', '<|im_end|>', '<|endoftext|>'],
          'emitPartialCompletion': false,
        });

        return <String, dynamic>{
          'text': '这是本地模型回答。',
          'finishReason': 'stop',
          'usedPrivateContext': false,
        };
      });

      addTearDown(() => messenger.setMockMethodCallHandler(methodChannel, null));

      final bridge = MethodChannelLlmRuntimeBridge(channel: methodChannel);
      final result = await bridge.generateText(
        modelId: 'phi-mini',
        modelPath: '/data/user/0/app/files/models/phi.gguf',
        prompt: '你好',
        usedPrivateContext: false,
        maxOutputTokens: 96,
        maxPromptChars: 1200,
        contextLength: 1024,
        conservativeMode: true,
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        seed: 42,
        stopSequences: const <String>['</s>', '<|im_end|>', '<|endoftext|>'],
        emitPartialCompletion: false,
      );

      expect(result, <String, dynamic>{
        'text': '这是本地模型回答。',
        'finishReason': 'stop',
        'usedPrivateContext': false,
      });
    });
  });
}
