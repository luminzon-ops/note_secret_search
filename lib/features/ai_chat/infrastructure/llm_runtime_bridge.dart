import 'package:flutter/services.dart';

class LlmRuntimeException implements Exception {
  const LlmRuntimeException({
    required this.code,
    this.stage,
    this.modelId,
    this.requestId,
  });

  final String code;
  final String? stage;
  final String? modelId;
  final String? requestId;

  bool get isCancellation => false;

  @override
  String toString() => 'LlmRuntimeException($code)';

  static LlmRuntimeException fromPlatformException(
    PlatformException error, {
    required String fallbackCode,
  }) {
    final code = _knownErrorCodes.contains(error.code)
        ? error.code
        : fallbackCode;
    final stage = _stringDetail(error.details, 'stage');
    final modelId = _stringDetail(error.details, 'modelId');
    final requestId = _stringDetail(error.details, 'requestId');
    if (code == 'CANCELLED') {
      return LlmRuntimeCancelledException(
        stage: stage,
        modelId: modelId,
        requestId: requestId,
      );
    }
    return LlmRuntimeException(
      code: code,
      stage: stage,
      modelId: modelId,
      requestId: requestId,
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
    'MODEL_UNSUPPORTED',
    'BUSY',
    'CANCELLED',
    'LOAD_FAILED',
    'GENERATION_FAILED',
    'RELEASE_FAILED',
    'RUNTIME_CLOSED',
  };
}

class LlmRuntimeCancelledException extends LlmRuntimeException {
  const LlmRuntimeCancelledException({
    super.stage,
    super.modelId,
    super.requestId,
  }) : super(code: 'CANCELLED');

  @override
  bool get isCancellation => true;
}

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

abstract interface class RequestIdentifiedLlmRuntimeBridge {
  Future<Map<String, dynamic>> ensureIdentifiedModelReady({
    required String modelId,
    required String modelPath,
    required String? verifiedChecksum,
  });

  Future<Map<String, dynamic>> generateIdentifiedText({
    required String requestId,
    required String modelId,
    required String modelPath,
    required String? verifiedChecksum,
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

  Future<void> cancelGeneration({required String requestId});
}

class MethodChannelLlmRuntimeBridge
    implements LlmRuntimeBridge, RequestIdentifiedLlmRuntimeBridge {
  MethodChannelLlmRuntimeBridge({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('note_secret_search/llm_runtime');

  final MethodChannel _channel;

  @override
  Future<Map<String, dynamic>> inspectModel({
    required String modelId,
    required String modelPath,
  }) async {
    final result = await _invokeMap('inspectModel', <String, Object?>{
      'modelId': modelId,
      'modelPath': modelPath,
    }, fallbackCode: 'LOAD_FAILED');
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> ensureModelReady({
    required String modelId,
    required String modelPath,
  }) async {
    final result = await _invokeMap('ensureModelReady', <String, Object?>{
      'modelId': modelId,
      'modelPath': modelPath,
    }, fallbackCode: 'LOAD_FAILED');
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> ensureIdentifiedModelReady({
    required String modelId,
    required String modelPath,
    required String? verifiedChecksum,
  }) async {
    final result = await _invokeMap('ensureModelReady', <String, Object?>{
      'modelId': modelId,
      'modelPath': modelPath,
      'verifiedChecksum': verifiedChecksum,
    }, fallbackCode: 'LOAD_FAILED');
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
    final result = await _invokeMap('generateText', <String, Object?>{
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
    }, fallbackCode: 'GENERATION_FAILED');
    return result ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> generateIdentifiedText({
    required String requestId,
    required String modelId,
    required String modelPath,
    required String? verifiedChecksum,
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
    final result = await _invokeMap('generateText', <String, Object?>{
      'requestId': requestId,
      'modelId': modelId,
      'modelPath': modelPath,
      'verifiedChecksum': verifiedChecksum,
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
    }, fallbackCode: 'GENERATION_FAILED');
    return result ?? <String, dynamic>{};
  }

  @override
  Future<void> cancelGeneration({required String requestId}) async {
    await _invoke<void>('cancelGeneration', <String, Object?>{
      'requestId': requestId,
    }, fallbackCode: 'GENERATION_FAILED');
  }

  @override
  Future<void> releaseModel({required String modelId}) async {
    await _invoke<void>('releaseModel', <String, Object?>{
      'modelId': modelId,
    }, fallbackCode: 'RELEASE_FAILED');
  }

  Future<T?> _invoke<T>(
    String method,
    Map<String, Object?> arguments, {
    required String fallbackCode,
  }) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw LlmRuntimeException.fromPlatformException(
        error,
        fallbackCode: fallbackCode,
      );
    }
  }

  Future<Map<String, dynamic>?> _invokeMap(
    String method,
    Map<String, Object?> arguments, {
    required String fallbackCode,
  }) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(method, arguments);
    } on PlatformException catch (error) {
      throw LlmRuntimeException.fromPlatformException(
        error,
        fallbackCode: fallbackCode,
      );
    }
  }
}
