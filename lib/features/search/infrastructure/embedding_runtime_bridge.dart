import 'package:flutter/services.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';

class EmbeddingModelMetadata {
  const EmbeddingModelMetadata({required this.tokenizer, required this.runtime});

  final EmbeddingTokenizerSpec tokenizer;
  final EmbeddingRuntimeSpec runtime;
}

abstract interface class EmbeddingRuntimeBridge {
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  });

  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  });

  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
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
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'inspectModel',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
        'tokenizer': _tokenizerPayload(tokenizer),
        'runtime': _runtimePayload(runtime),
      },
    );
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'ensureModelReady',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
        'tokenizer': _tokenizerPayload(tokenizer),
        'runtime': _runtimePayload(runtime),
      },
    );
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'embedText',
      <String, Object?>{
        'modelId': modelId,
        'modelPath': modelPath,
        'text': text,
        'tokenizer': _tokenizerPayload(tokenizer),
        'runtime': _runtimePayload(runtime),
      },
    );
    return result ?? <String, dynamic>{};
  }

  @override
  Future<void> releaseModel({required String modelId}) async {
    await _channel.invokeMethod<void>('releaseModel', <String, Object?>{'modelId': modelId});
  }

  Map<String, Object?>? _tokenizerPayload(EmbeddingTokenizerSpec? tokenizer) {
    if (tokenizer == null) {
      return null;
    }

    return <String, Object?>{
      'format': tokenizer.format,
      'assetPath': tokenizer.assetPath,
      'maxSequenceLength': tokenizer.maxSequenceLength,
      'lowercase': tokenizer.lowercase,
    };
  }

  Map<String, Object?>? _runtimePayload(EmbeddingRuntimeSpec? runtime) {
    if (runtime == null) {
      return null;
    }

    return <String, Object?>{
      'inputIdsName': runtime.inputIdsName,
      'attentionMaskName': runtime.attentionMaskName,
      'tokenTypeIdsName': runtime.tokenTypeIdsName,
      'outputName': runtime.outputName,
      'pooling': runtime.pooling,
      'normalization': runtime.normalization,
    };
  }
}
