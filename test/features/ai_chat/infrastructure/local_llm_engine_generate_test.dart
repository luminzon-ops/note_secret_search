import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/domain/llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/local_llm_engine.dart';
import 'package:note_secret_search/features/ai_chat/infrastructure/llm_runtime_bridge.dart';
import 'package:note_secret_search/features/ai_models/domain/model_registry_entry.dart';

void main() {
  test('generate maps bridge payload into inference response', () async {
    final bridge = _FakeLlmRuntimeBridge(
      generateTextResult: {
        'text': '这是 Android 本地 LLM 的回答。',
        'finishReason': 'stop',
        'usedPrivateContext': true,
      },
    );
    final engine = LocalLlmEngine(bridge: bridge);

    final response = await engine.generate(
      const LlmInferenceRequest(
        model: _installedLlmModel,
        prompt: '请总结这段内容。',
        usedPrivateContext: true,
        maxOutputTokens: 96,
        maxPromptChars: 1200,
        contextLength: 1024,
        conservativeMode: true,
      ),
    );

    expect(response.text, '这是 Android 本地 LLM 的回答。');
    expect(response.finishReason, 'stop');
    expect(response.usedPrivateContext, isTrue);
    expect(bridge.generateTextCalls, hasLength(1));
    expect(
      bridge.generateTextCalls.single,
      const _GenerateTextCall(
        modelId: 'qwen-local',
        modelPath: '/data/user/0/app/files/models/qwen.gguf',
        prompt: '请总结这段内容。',
        usedPrivateContext: true,
        maxOutputTokens: 96,
        maxPromptChars: 1200,
        contextLength: 1024,
        conservativeMode: true,
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        seed: 42,
        stopSequences: <String>['</s>', '<|im_end|>', '<|endoftext|>'],
      ),
    );
  });

  test('generate throws before touching bridge when active model path is missing', () async {
    final bridge = _FakeLlmRuntimeBridge(
      generateTextResult: {
        'text': 'unexpected',
        'finishReason': 'stop',
        'usedPrivateContext': false,
      },
    );
    final engine = LocalLlmEngine(bridge: bridge);

    expect(
      () => engine.generate(
        const LlmInferenceRequest(
          model: _missingPathLlmModel,
          prompt: '你好',
          usedPrivateContext: false,
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(bridge.generateTextCalls, isEmpty);
  });
}

const _installedLlmModel = ModelRegistryEntry(
  id: 'qwen-local',
  type: 'llm',
  provider: 'builtin',
  name: 'Qwen Local',
  version: '1.0.0',
  sizeBytes: 1024,
  quantization: 'Q4_K_M',
  minRamMb: 2048,
  recommendedTier: 'mvp',
  localPath: '/data/user/0/app/files/models/qwen.gguf',
  checksum: 'sha256:qwen',
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
);

const _missingPathLlmModel = ModelRegistryEntry(
  id: 'qwen-missing-path',
  type: 'llm',
  provider: 'builtin',
  name: 'Qwen Missing Path',
  version: '1.0.0',
  sizeBytes: 1024,
  quantization: 'Q4_K_M',
  minRamMb: 2048,
  recommendedTier: 'mvp',
  localPath: '',
  checksum: 'sha256:qwen',
  enabled: true,
  installedAt: null,
  filePresent: true,
  integrityStatus: ModelIntegrityStatus.valid,
);

class _FakeLlmRuntimeBridge implements LlmRuntimeBridge {
  _FakeLlmRuntimeBridge({required this.generateTextResult});

  final Map<String, dynamic> generateTextResult;
  final List<_GenerateTextCall> generateTextCalls = <_GenerateTextCall>[];

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  }) async {
    return <String, dynamic>{
      'ready': true,
      'reason': 'ready',
      'status': 'ready',
      'modelPath': modelPath,
    };
  }

  @override
  Future<Map<String, dynamic>> generateText({
    required String modelId,
    required String modelPath,
    required String prompt,
    required bool usedPrivateContext,
    required int maxOutputTokens,
    required int maxPromptChars,
    required int contextLength,
    required bool conservativeMode,
    required double temperature,
    required int topK,
    required double topP,
    required int seed,
    required List<String> stopSequences,
  }) async {
    generateTextCalls.add(
      _GenerateTextCall(
        modelId: modelId,
        modelPath: modelPath,
        prompt: prompt,
        usedPrivateContext: usedPrivateContext,
        maxOutputTokens: maxOutputTokens,
        maxPromptChars: maxPromptChars,
        contextLength: contextLength,
        conservativeMode: conservativeMode,
        temperature: temperature,
        topK: topK,
        topP: topP,
        seed: seed,
        stopSequences: stopSequences,
      ),
    );
    return generateTextResult;
  }

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  }) async {
    return <String, dynamic>{
      'ready': false,
      'reason': 'installed but unverified',
      'status': 'installed_unverified',
      'modelPath': modelPath,
    };
  }

  @override
  Future<void> releaseModel({required String modelId}) async {}
}

class _GenerateTextCall {
  const _GenerateTextCall({
    required this.modelId,
    required this.modelPath,
    required this.prompt,
    required this.usedPrivateContext,
    required this.maxOutputTokens,
    required this.maxPromptChars,
    required this.contextLength,
    required this.conservativeMode,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.seed,
    required this.stopSequences,
  });

  final String modelId;
  final String modelPath;
  final String prompt;
  final bool usedPrivateContext;
  final int maxOutputTokens;
  final int maxPromptChars;
  final int contextLength;
  final bool conservativeMode;
  final double temperature;
  final int topK;
  final double topP;
  final int seed;
  final List<String> stopSequences;

  @override
  bool operator ==(Object other) {
    return other is _GenerateTextCall &&
        other.modelId == modelId &&
        other.modelPath == modelPath &&
        other.prompt == prompt &&
        other.usedPrivateContext == usedPrivateContext &&
        other.maxOutputTokens == maxOutputTokens &&
        other.maxPromptChars == maxPromptChars &&
        other.contextLength == contextLength &&
        other.conservativeMode == conservativeMode &&
        other.temperature == temperature &&
        other.topK == topK &&
        other.topP == topP &&
        other.seed == seed &&
        listEquals(other.stopSequences, stopSequences);
  }

  @override
  int get hashCode => Object.hash(
    modelId,
    modelPath,
    prompt,
    usedPrivateContext,
    maxOutputTokens,
    maxPromptChars,
    contextLength,
    conservativeMode,
  );
}
