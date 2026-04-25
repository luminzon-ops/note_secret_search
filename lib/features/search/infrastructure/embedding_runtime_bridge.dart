import 'package:flutter/services.dart';

abstract interface class EmbeddingRuntimeBridge {
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  });

  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  });

  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
  });

  Future<void> releaseModel({required String modelId});
}

class MethodChannelEmbeddingRuntimeBridge implements EmbeddingRuntimeBridge {
  MethodChannelEmbeddingRuntimeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('note_secret_search/embedding_runtime');

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
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'embedText',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
        'text': text,
      },
    );
    return result ?? <String, dynamic>{};
  }

  @override
  Future<void> releaseModel({required String modelId}) async {
    await _channel.invokeMethod<void>('releaseModel', <String, Object?>{'modelId': modelId});
  }
}
