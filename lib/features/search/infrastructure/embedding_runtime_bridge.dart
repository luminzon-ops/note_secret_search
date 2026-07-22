import 'package:flutter/services.dart';
import 'package:note_secret_search/features/ai_models/domain/model_catalog_entry.dart';
import 'package:note_secret_search/features/search/domain/embedding_engine.dart';

class EmbeddingRuntimeException implements Exception {
  const EmbeddingRuntimeException({
    required this.code,
    this.stage,
    this.modelId,
  });

  final String code;
  final String? stage;
  final String? modelId;

  bool get isCancellation => false;

  @override
  String toString() {
    final suffix = modelId == null ? '' : ' model=$modelId';
    return 'EmbeddingRuntimeException($code$suffix)';
  }

  static EmbeddingRuntimeException fromPlatformException(
    PlatformException error,
  ) {
    final details = error.details;
    final code = _knownErrorCodes.contains(error.code)
        ? error.code
        : 'ORT_FAILURE';
    final stage = _stringDetail(details, 'stage');
    final modelId = _stringDetail(details, 'modelId');
    if (code == 'CANCELLED') {
      return EmbeddingRuntimeCancelledException(stage: stage, modelId: modelId);
    }
    return EmbeddingRuntimeException(
      code: code,
      stage: stage,
      modelId: modelId,
    );
  }

  static String? _stringDetail(Object? details, String name) {
    if (details is! Map) {
      return null;
    }
    final value = details[name];
    return value is String ? value : null;
  }

  static const _knownErrorCodes = <String>{
    'INVALID_ARGUMENT',
    'MODEL_MISSING',
    'CHECKSUM_MISMATCH',
    'TOKENIZER_SCHEMA_UNSUPPORTED',
    'MODEL_SCHEMA_UNSUPPORTED',
    'INVALID_OUTPUT',
    'BUSY',
    'CANCELLED',
    'RUNTIME_CLOSED',
    'ORT_FAILURE',
  };
}

class EmbeddingRuntimeCancelledException extends EmbeddingRuntimeException
    implements EmbeddingCancellationException {
  const EmbeddingRuntimeCancelledException({super.stage, super.modelId})
    : super(code: 'CANCELLED');

  @override
  bool get isCancellation => true;
}

class EmbeddingModelMetadata {
  const EmbeddingModelMetadata({
    required this.tokenizer,
    required this.runtime,
  });

  final EmbeddingTokenizerSpec tokenizer;
  final EmbeddingRuntimeSpec runtime;
}

abstract interface class EmbeddingRuntimeBridge {
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  });

  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  });

  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
    String? requestId,
  });

  Future<void> cancelRequest({required String requestId});

  Future<void> releaseModel({required String modelId});
}

class MethodChannelEmbeddingRuntimeBridge implements EmbeddingRuntimeBridge {
  MethodChannelEmbeddingRuntimeBridge({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('note_secret_search/embedding_runtime');

  final MethodChannel _channel;

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) async {
    final result = await _invokeMap('inspectModel', <String, Object?>{
      'modelId': modelId,
      'modelPath': modelPath,
      'tokenizer': _tokenizerPayload(tokenizer),
      'runtime': _runtimePayload(runtime),
      'verifiedChecksum': verifiedChecksum,
    });
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
  }) async {
    final result = await _invokeMap('ensureModelReady', <String, Object?>{
      'modelId': modelId,
      'modelPath': modelPath,
      'tokenizer': _tokenizerPayload(tokenizer),
      'runtime': _runtimePayload(runtime),
      'verifiedChecksum': verifiedChecksum,
    });
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> embedText({
    required String modelId,
    required String modelPath,
    required String text,
    EmbeddingTokenizerSpec? tokenizer,
    EmbeddingRuntimeSpec? runtime,
    String? verifiedChecksum,
    String? requestId,
  }) async {
    final result = await _invokeMap('embedText', <String, Object?>{
      'modelId': modelId,
      'modelPath': modelPath,
      'text': text,
      'tokenizer': _tokenizerPayload(tokenizer),
      'runtime': _runtimePayload(runtime),
      'verifiedChecksum': verifiedChecksum,
      'requestId': requestId,
    });
    return result ?? <String, dynamic>{};
  }

  @override
  Future<void> cancelRequest({required String requestId}) async {
    await _invoke<void>('cancelRequest', <String, Object?>{
      'requestId': requestId,
    });
  }

  @override
  Future<void> releaseModel({required String modelId}) async {
    await _invoke<void>('releaseModel', <String, Object?>{'modelId': modelId});
  }

  Future<T?> _invoke<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw EmbeddingRuntimeException.fromPlatformException(error);
    }
  }

  Future<Map<String, dynamic>?> _invokeMap(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(method, arguments);
    } on PlatformException catch (error) {
      throw EmbeddingRuntimeException.fromPlatformException(error);
    }
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
