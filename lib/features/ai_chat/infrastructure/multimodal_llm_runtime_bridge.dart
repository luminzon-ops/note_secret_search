import 'package:flutter/services.dart';

abstract interface class MultimodalLlmRuntimeBridge {
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    required String mmprojPath,
  });

  Future<Map<String, dynamic>> generateMultimodalText({
    required String modelId,
    required String modelPath,
    required String mmprojPath,
    required String imagePath,
    required String prompt,
    required int maxOutputTokens,
    required int contextLength,
    required bool reasoningEnabled,
  });
}

class MethodChannelMultimodalLlmRuntimeBridge implements MultimodalLlmRuntimeBridge {
  MethodChannelMultimodalLlmRuntimeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('note_secret_search/llm_runtime');

  final MethodChannel _channel;

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    required String mmprojPath,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'ensureMultimodalModelReady',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
        'mmprojPath': mmprojPath,
      },
    );
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> generateMultimodalText({
    required String modelId,
    required String modelPath,
    required String mmprojPath,
    required String imagePath,
    required String prompt,
    required int maxOutputTokens,
    required int contextLength,
    required bool reasoningEnabled,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'generateMultimodalText',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
        'mmprojPath': mmprojPath,
        'imagePath': imagePath,
        'prompt': prompt,
        'maxOutputTokens': maxOutputTokens,
        'contextLength': contextLength,
        'reasoningEnabled': reasoningEnabled,
      },
    );
    return result ?? <String, dynamic>{};
  }
}
