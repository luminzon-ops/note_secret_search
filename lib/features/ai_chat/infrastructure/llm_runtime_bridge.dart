import 'package:flutter/services.dart';

abstract interface class LlmRuntimeBridge {
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  });

  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  });

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
    required bool emitPartialCompletion,
  });

  Future<void> releaseModel({required String modelId});
}

class MethodChannelLlmRuntimeBridge implements LlmRuntimeBridge {
  MethodChannelLlmRuntimeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('note_secret_search/llm_runtime');

  final MethodChannel _channel;

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'inspectModel',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
      },
    );
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'ensureModelReady',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
      },
    );
    return result ?? <String, dynamic>{};
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
    required bool emitPartialCompletion,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'generateText',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
        'prompt': prompt,
        'usedPrivateContext': usedPrivateContext,
        'maxOutputTokens': maxOutputTokens,
        'maxPromptChars': maxPromptChars,
        'contextLength': contextLength,
        'conservativeMode': conservativeMode,
        'temperature': temperature,
        'topK': topK,
        'topP': topP,
        'seed': seed,
        'stopSequences': stopSequences,
        'emitPartialCompletion': emitPartialCompletion,
      },
    );
    return result ?? <String, dynamic>{};
  }

  @override
  Future<void> releaseModel({required String modelId}) async {
    await _channel.invokeMethod<void>('releaseModel', <String, Object?>{'modelId': modelId});
  }
}
