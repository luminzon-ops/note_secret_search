import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/multimodal_llm_runtime_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generateMultimodalText sends model mmproj image and reasoning off', () async {
    const channel = MethodChannel('test/multimodal_llm_runtime');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'status': 'ready', 'text': 'A cat', 'finishReason': 'stop'};
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    final bridge = MethodChannelMultimodalLlmRuntimeBridge(channel: channel);
    final result = await bridge.generateMultimodalText(
      modelId: 'minicpm_v_4_6_q4_k_m',
      modelPath: '/models/model.gguf',
      mmprojPath: '/models/mmproj-model-f16.gguf',
      imagePath: '/cache/input.jpg',
      prompt: 'Describe it',
      maxOutputTokens: 96,
      contextLength: 1024,
      reasoningEnabled: false,
    );

    expect(result['text'], 'A cat');
    expect(calls.single.method, 'generateMultimodalText');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments, containsPair('modelPath', '/models/model.gguf'));
    expect(arguments, containsPair('mmprojPath', '/models/mmproj-model-f16.gguf'));
    expect(arguments, containsPair('imagePath', '/cache/input.jpg'));
    expect(arguments, containsPair('prompt', 'Describe it'));
    expect(arguments, containsPair('reasoningEnabled', false));
  });

  test('ensureMultimodalModelReady sends model and mmproj paths', () async {
    const channel = MethodChannel('test/multimodal_llm_runtime_ready');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'status': 'runtime_unavailable', 'ready': false};
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    final bridge = MethodChannelMultimodalLlmRuntimeBridge(channel: channel);
    final result = await bridge.ensureModelReady(
      modelId: 'minicpm_v_4_6_q4_k_m',
      modelPath: '/models/model.gguf',
      mmprojPath: '/models/mmproj-model-f16.gguf',
    );

    expect(result['status'], 'runtime_unavailable');
    expect(calls.single.method, 'ensureMultimodalModelReady');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments, containsPair('modelId', 'minicpm_v_4_6_q4_k_m'));
    expect(arguments, containsPair('modelPath', '/models/model.gguf'));
    expect(arguments, containsPair('mmprojPath', '/models/mmproj-model-f16.gguf'));
  });
}
